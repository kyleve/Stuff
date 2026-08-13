# WhereCrashReporting – Module Shape

WhereCrashReporting is the Where app's vendor-neutral boundary around its
process-global crash-reporting SDK. See [`README.md`](README.md). This file
complements the root [`AGENTS.md`](../../AGENTS.md). That file owns build,
formatting, and repository-wide conventions.

## Scope and invariants

- Keep every vendor API inside its own `WhereCrashReporting` conformer in this
  module.
- Construct one conformer per enabled service at the app composition root.
  Start each exactly once before the selected application runtime receives
  `didFinishLaunching`.
- Keep crash reporting independent of performance tracing. Tracing requires a
  separate product decision and sampling policy.
- Keep project-specific client configuration at the app composition root.
- Do not start the process-global SDK under XCTest. Detect the test process via
  `XCTestConfigurationFilePath` before touching the vendor.

## Testing

Swift Testing lives in [`Tests/`](Tests). Test each conformer's configuration
mapping and the shared process gate without starting a process-global SDK. The
app wiring test verifies every conformer starts before its runtime.
