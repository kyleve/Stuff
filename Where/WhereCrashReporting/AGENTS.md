# WhereCrashReporting – Module Shape

WhereCrashReporting is the Where app's narrow adapter around the Sentry Apple
SDK. See [`README.md`](README.md). This file complements the root
[`AGENTS.md`](../../AGENTS.md), which owns build, formatting, and repository-wide
conventions.

## Scope and invariants

- Depend only on Sentry and keep every vendor API inside this module.
- Start Sentry exactly once from the Where app's `AppDelegate`, before the
  selected application runtime receives `didFinishLaunching`.
- Keep crash reporting independent of performance tracing; tracing requires a
  separate product decision and sampling policy.
- Keep the project-specific public DSN at the app composition root.
- Do not start the process-global SDK under XCTest; detect the test process via
  `XCTestConfigurationFilePath` before touching Sentry.

## Testing

Swift Testing lives in [`Tests/`](Tests). Test configuration mapping without
starting the process-global SDK; the app build verifies the integration.
