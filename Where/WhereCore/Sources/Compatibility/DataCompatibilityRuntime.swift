import Foundation

/// Quiesces a resolved scope while retaining recording consent and its existing retry backlog.
public struct DataCompatibilityRuntime: Sendable {
    let recording: DeviceRecordingController
    let resolution: DataIssueScanner
    let outputs: DataCompatibilityOutputs
    let widgets: WidgetSnapshotPublisher

    public func suspend() async {
        async let paused: Void = recording.suspendForCompatibility()
        await resolution.invalidate()
        await outputs.withdraw()
        await paused
        await widgets.invalidate()
    }
}
