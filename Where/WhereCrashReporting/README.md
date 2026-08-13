# WhereCrashReporting

The Where app's vendor-neutral crash-reporting boundary. The app delegate
constructs one `WhereCrashReporting` implementation per enabled service and
starts each one before forwarding launch to the selected application runtime.
The module currently adapts Bitdrift Capture without exposing its SDK to the
application target.

```swift
let reporters: [any WhereCrashReporting] = [
    BitdriftCrashReporter(apiKey: bitdriftAPIKey),
]
reporters.forEach { $0.start() }
```

The app owns the service-specific client configuration and passes it at the
composition root. This module contains no environment-specific project
configuration. Performance tracing remains separate from this setup.

Processes carrying Xcode's `XCTestConfigurationFilePath` environment value do
not start the process-global SDK. Automated test activity stays out of the
production project.
