import SnapshotKit
@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import Synchronization
import TestHostSupport
import Testing

@MainActor
struct AssertSnapshotsTests {
    @Test func exhaustedConfigurationRecordsOnceAndContinuesToTheNext() async {
        var attempts = 0
        let failures = Mutex(0)
        await withKnownIssue("Two configurations exhaust their retries", isIntermittent: false) {
            await assertSnapshots(
                of: Color.green.frame(width: 40, height: 40),
                named: "exhausted",
                configurations: [.init(), .init(colorScheme: .dark)],
                measurementReadiness: .immediate,
                onReadyToMeasure: {
                    attempts += 1
                    throw snapshotRetryTimeout(attempt: attempts)
                },
                settle: .immediate,
                record: .never,
            )
        } matching: { issue in
            guard let error = issue.error as? SnapshotRenderingError,
                  error == snapshotRetryTimeout(attempt: 3)
                  || error == snapshotRetryTimeout(attempt: 6)
            else { return false }
            failures.withLock { $0 += 1 }
            return true
        }
        #expect(attempts == 6)
        #expect(failures.withLock { $0 } == 2)
    }

    @Test(arguments: [1, 3])
    func recoveredCaptureReachesComparisonOnlyOnce(successfulAttempt: Int) async {
        var attempts = 0
        let comparisons = Mutex(0)
        await withKnownIssue("The probe deliberately has no reference", isIntermittent: false) {
            await assertSnapshots(
                of: Color.green.frame(width: 40, height: 40),
                named: "recovered-without-reference",
                configurations: [.init()],
                measurementReadiness: .immediate,
                onReadyToMeasure: {
                    attempts += 1
                    if attempts < successfulAttempt {
                        throw snapshotRetryTimeout(attempt: attempts)
                    }
                },
                settle: .immediate,
                record: .never,
            )
        } matching: { issue in
            guard issue.error == nil,
                  issue.comments.contains(where: { $0.rawValue.contains("No reference was found") })
            else { return false }
            comparisons.withLock { $0 += 1 }
            return true
        }
        #expect(attempts == successfulAttempt)
        #expect(comparisons.withLock { $0 } == 1)
    }

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
