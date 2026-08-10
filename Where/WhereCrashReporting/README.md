# WhereCrashReporting

The Where app's vendor-neutral crash-reporting boundary. The app delegate
constructs one `WhereCrashReporting` implementation per enabled service and
starts each one before forwarding launch to the selected application runtime.
The module currently adapts Sentry and Bitdrift Capture without exposing either
SDK to the application target.

```swift
let reporters: [any WhereCrashReporting] = [
    SentryCrashReporter(dsn: publicDSN, debug: isDebugBuild),
    BitdriftCrashReporter(apiKey: bitdriftAPIKey),
]
reporters.forEach { $0.start() }
```

The app owns the service-specific client configuration and passes it at the
composition root, so this module contains no environment-specific project
configuration. Sentry performance tracing remains disabled by this setup.

Processes carrying Xcode's `XCTestConfigurationFilePath` environment value do
not start either process-global SDK, keeping automated test activity out of the
production projects.
