# WhereCrashReporting – Module Shape

WhereCrashReporting is the Where app's vendor boundary around its
process-global diagnostic-reporting SDK. See [`README.md`](README.md). This file
complements the root [`AGENTS.md`](../../AGENTS.md). That file owns build,
formatting, and repository-wide conventions.

## Scope and invariants

- Keep every vendor API inside this module. Expose only launch configuration,
  sleeping, and typed log-write values to app composition.
- Configure fatal reporting and replay explicitly from the process launch
  snapshot. Never inherit a vendor default.
- Keep the Periscope sink and preference types outside this module. Then another
  provider can replace Bitdrift without changing persisted choices.
- Keep crash reporting independent of performance tracing. Tracing requires a
  separate product decision and sampling policy.
- Keep project-specific client configuration at the app composition root.
- Do not start the process-global SDK under XCTest. Detect the test process via
  `XCTestConfigurationFilePath` before touching the vendor.

## Testing

Swift Testing lives in [`Tests/`](Tests). Test the adapter value mapping and
shared process gate without starting a process-global SDK. The app tests own the
controller matrix and launch ordering.
