# WhereCrashReporting

The Where app's vendor adapter for process-level diagnostic reporting. It wraps
Bitdrift Capture behind `BitdriftReportingClient`, launch configuration, and a
Sendable log writer. No other module imports the vendor SDK.

The app composition root owns the reporting controller. It snapshots the
vendor-neutral `DiagnosticReportingConfiguration` from `WherePreferences`.
It starts Bitdrift only when crash reports, session replay, or remote logs
require it. It also owns the Periscope sink. Crash and replay are fixed for the
process. Remote-log threshold and metadata policy reconcile live.

Bitdrift startup errors cross the vendor boundary as errors. The app records a
typed local event with the error attachment. It converts the error to text only
for the Settings failure state.

Session replay is passed explicitly as either a configuration or `nil`. It does
not inherit Bitdrift's enabled SDK default. Processes carrying Xcode's
`XCTestConfigurationFilePath` do not start the process-global SDK. Performance
tracing remains a separate product decision.
