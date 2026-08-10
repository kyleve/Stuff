# WhereCrashReporting

The Where app's narrow adapter around the Sentry Apple SDK. The app delegate
starts it once, before forwarding launch to the selected application runtime.
The module enables crash reporting and SDK diagnostic output when requested;
it does not opt the app into performance tracing.

```swift
WhereCrashReporting.start(dsn: publicDSN, debug: isDebugBuild)
```

The Sentry DSN is a public routing identifier, not an authentication secret.
The app owns its value and passes it at the composition root so this module
contains no environment-specific project configuration.

Processes carrying Xcode's `XCTestConfigurationFilePath` environment value do
not start Sentry, keeping automated test activity out of the production crash
project.
