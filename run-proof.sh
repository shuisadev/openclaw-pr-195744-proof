#!/usr/bin/env bash
# Shipped macOS Doctor proof for OpenClaw PR #195744.
# Runs on GitHub Actions macos-latest. Proves that the shipped macOS Doctor path warns
# when the stale-updater launchctl scan fails (exit 1, "Operation not permitted")
# instead of reporting healthy, using a real native launchctl stub on PATH.
set -uo pipefail

PROOF=/tmp/proof
PKG="${PKG:-$PWD}"
NODE_BIN="$(command -v node)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STUB_DIR="$PROOF/stub-bin"
STATE_DIR="$PROOF/state"

mkdir -p "$PROOF" "$STUB_DIR" "$STATE_DIR"
export OPENCLAW_STATE_DIR="$STATE_DIR"
export OPENCLAW_NO_AUTO_UPDATE=1

say() { echo "[proof] $*"; }
head_step() { echo; echo "############ $* ############"; }
dump() { echo "===== $1 ====="; shift; "$@" 2>&1 | sed 's/^/  /' || true; echo; }

say "node=$($NODE_BIN -v) platform=$(uname -s) arch=$(uname -m)"

# ---------------------------------------------------------------- native launchctl stub
head_step "STAGE native launchctl stub"
# The shipped execLaunchctl resolves the bare name "launchctl" through PATH, so a
# stub earlier on PATH intercepts it. It fails exactly like launchd denying the call.
cat >"$STUB_DIR/launchctl" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "list" ]; then
  echo "Operation not permitted" >&2
  exit 1
fi
# Other launchctl reads behave like the real one: no output, success.
exit 0
SH
chmod +x "$STUB_DIR/launchctl"
export PATH="$STUB_DIR:$PATH"
say "stub launchctl installed at $STUB_DIR/launchctl (PATH-first)"
dump "stub self-check (list)" "$STUB_DIR/launchctl" list

# ---------------------------------------------------------------- driver
head_step "STAGE shipped doctor warning"
# Call the exact production function the macOS Doctor startup flow invokes for this
# warning (noteMacGatewayPlatformWarnings -> collectMacStaleOpenClawUpdateLaunchdJobsWarning
# -> findStaleOpenClawUpdateLaunchdJobs -> execLaunchctl(["list"])). The native stub returns
# exit 1 + "Operation not permitted", so the collector must surface the failure warning.
cat >"$PKG/proof-driver.mts" <<'DRIVER'
import { noteMacGatewayPlatformWarnings } from "./src/commands/doctor-platform-notes.ts";
try {
  await noteMacGatewayPlatformWarnings({ gateway: { mode: "local" } }, undefined, process.env);
} catch (error) {
  // The warning loop prints via note() before the (independently guarded) env inspection;
  // any later throw must not hide the already-emitted stale-updater warning.
  console.error("[driver] post-warning step threw (expected to be self-guarded):", String(error).slice(0, 200));
}
DRIVER
(cd "$PKG" && OPENCLAW_STATE_DIR="$STATE_DIR" "$NODE_BIN" --import ./scripts/tsx.mjs ./proof-driver.mts >"$PROOF/doctor.log" 2>&1)
rm -f "$PKG/proof-driver.mts"
dump "shipped doctor terminal output" cat "$PROOF/doctor.log"

# ---------------------------------------------------------------- verify
head_step "STAGE verify"
WARN_MSG="$(grep -F "Could not inspect stale OpenClaw updater launchd jobs" "$PROOF/doctor.log" || true)"
EXIT_OK=0; PERM_OK=0; NOT_CHECKED=0
[ -n "$WARN_MSG" ] && NOT_CHECKED=1
echo "$WARN_MSG" | grep -qF "exit 1" && EXIT_OK=1
echo "$WARN_MSG" | grep -qF "Operation not permitted" && PERM_OK=1

say "warning_present=$NOT_CHECKED exit_1_detail=$EXIT_OK operation_not_permitted_detail=$PERM_OK"
if [ "$NOT_CHECKED" = "1" ] && [ "$EXIT_OK" = "1" ] && [ "$PERM_OK" = "1" ]; then
  say "VERDICT pass: shipped macOS Doctor warned with the launchctl failure details instead of reporting healthy"
  exit 0
fi
say "VERDICT fail: warning_present=$NOT_CHECKED exit_1_detail=$EXIT_OK operation_not_permitted_detail=$PERM_OK"
exit 1
