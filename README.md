# Shipped macOS Doctor proof — OpenClaw PR #195744

Real-behavior proof that the shipped macOS Doctor path warns (instead of reporting
healthy) when the stale-updater `launchctl` scan fails.

## What it proves

PR #195744 changes the macOS stale-updater launchd scan so that when the native
`launchctl list` call fails, the Doctor CLI surfaces a warning that includes the
failure detail (exit code + `Operation not permitted`) instead of silently
reporting healthy.

This workflow runs the **shipped production code** (the exact functions the macOS
Doctor startup flow invokes: `noteMacGatewayPlatformWarnings` →
`collectMacStaleOpenClawUpdateLaunchdJobsWarning` →
`findStaleOpenClawUpdateLaunchdJobs` → `execLaunchctl(["list"])`) on a real
`macos-latest` runner.

The only mocked boundary is the native `launchctl` binary itself: a stub is placed
first on `PATH` so the shipped `execLaunchctl` (which resolves the bare name
`launchctl` through PATH) hits it and gets `exit 1` + `Operation not permitted` —
exactly what launchd returns when it denies the call. All other code is the real
shipped implementation.

## Trigger

`gh workflow run shipped-macos-doctor-proof` (optionally with `ref` input,
defaulting to the PR head branch).

## Output

`proof-output.txt` (also uploaded as an artifact) contains:

- the stub `launchctl` self-check (`Operation not permitted` on `list`),
- the shipped Doctor terminal output, which must contain the warning
  `Could not inspect stale OpenClaw updater launchd jobs ... exit 1 ... Operation not permitted ... NOT checked`,
- a `VERDICT pass/fail` line from the three-assertion check.
