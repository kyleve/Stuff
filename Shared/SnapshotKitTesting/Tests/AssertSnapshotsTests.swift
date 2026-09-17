import SnapshotKit
import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing

@MainActor
struct AssertSnapshotsTests {
    @Test func cancellationDuringMeasurementReadinessEndsQuietly() async throws {
        try waitFor { hostKeyWindow() != nil }
        let probe = MeasurementHookCancellationProbe()
        let assertion = Task { @MainActor in
            await assertSnapshots(
                of: Color.green.frame(width: 100, height: 100),
                named: "cancelled-measurement-readiness",
                configurations: [SnapshotConfiguration()],
                measurementReadiness: .immediate,
                onReadyToMeasure: {
                    probe.didStart = true
                    while Task.isCancelled == false {
                        await Task.yield()
                    }
                },
                settle: .immediate,
            )
        }

        while probe.didStart == false {
            await Task.yield()
        }
        assertion.cancel()
        await assertion.value
    }

    @Test func cancelledProviderDoesNotBuildItsNextCase() async throws {
        try waitFor { hostKeyWindow() != nil }
        let probe = MeasurementHookCancellationProbe()
        let hooks = ProviderCancellationHooks(
            waitForCancellation: {
                probe.didStart = true
                while Task.isCancelled == false {
                    await Task.yield()
                }
            },
            didBuildSecondCase: {
                probe.didBuildSecondCase = true
            },
        )

        await ProviderCancellationContext.$hooks.withValue(hooks) {
            let assertion = Task { @MainActor in
                await assertSnapshots(of: CancellationSnapshotProvider.self)
            }
            while probe.didStart == false {
                await Task.yield()
            }
            assertion.cancel()
            await assertion.value
        }

        #expect(probe.didBuildSecondCase == false)
    }
}

@MainActor
private final class MeasurementHookCancellationProbe {
    var didStart = false
    var didBuildSecondCase = false
}

private struct ProviderCancellationHooks {
    let waitForCancellation: @MainActor @Sendable () async -> Void
    let didBuildSecondCase: @MainActor @Sendable () -> Void
}

private enum ProviderCancellationContext {
    @TaskLocal static var hooks: ProviderCancellationHooks?
}

private struct CancellationSnapshotProvider: SnapshotProviding {
    @MainActor static var snapshots: [SnapshotCase] {
        let hooks = ProviderCancellationContext.hooks
        SnapshotCase(
            name: "cancelled-first-case",
            configurations: [
                SnapshotConfiguration(
                    device: SnapshotConfiguration.Frame(
                        name: "intrinsic",
                        size: .intrinsic(maxWidth: 100),
                    ),
                ),
            ],
            measurementReadiness: .immediate,
            onReadyToMeasure: hooks?.waitForCancellation,
            settle: .immediate,
        ) {
            Color.red.frame(height: 40)
        }
        SnapshotCase(
            name: "must-not-build",
            configurations: [SnapshotConfiguration()],
            settle: .immediate,
        ) {
            let _ = hooks?.didBuildSecondCase()
            Color.blue
        }
    }
}
