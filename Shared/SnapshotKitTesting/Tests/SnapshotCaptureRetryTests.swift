@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct SnapshotCaptureRetryTests {
    @Test(arguments: [1, 2, 3])
    func succeedsWithoutRetainingFailedControllers(successfulAttempt: Int) async throws {
        var attempts = 0
        var reports: [String] = []
        weak var previousController: UIViewController?
        let result = try await SnapshotCaptureRetry.capture(
            named: "retry-probe",
            makeViewController: {
                #expect(previousController == nil)
                let controller = UIViewController()
                previousController = controller
                return controller
            },
            capture: { _ in
                attempts += 1
                if attempts < successfulAttempt {
                    throw snapshotRetryTimeout(attempt: attempts)
                }
                return 42
            },
            report: { reports.append($0) },
        )
        #expect(result == 42)
        #expect(attempts == successfulAttempt)
        #expect(previousController == nil)
        #expect(reports.count == (successfulAttempt == 1 ? 0 : successfulAttempt))
        if successfulAttempt > 1 {
            #expect(reports.first?.contains("retrying attempt 2/3") == true)
            #expect(reports.last?.contains("recovered on attempt \(successfulAttempt)/3") == true)
        }
    }

    @Test(arguments: ["measurement", "content", "onReadyToSnapshot", "accessibility preparation"])
    func exhaustionPreservesTheFinalError(phase: String) async {
        var attempts = 0
        var reports: [String] = []
        await #expect(throws: snapshotRetryTimeout(attempt: 3, phase: phase)) {
            try await SnapshotCaptureRetry.capture(
                named: "retry-probe",
                makeViewController: { UIViewController() },
                capture: { _ -> Int in
                    attempts += 1
                    throw snapshotRetryTimeout(attempt: attempts, phase: phase)
                },
                report: { reports.append($0) },
            )
        }
        #expect(attempts == 3)
        #expect(reports.count == 2)
        #expect(reports.allSatisfy { $0.contains(phase) })
    }

    @Test func starvationCanRecover() async throws {
        var attempts = 0
        let result = try await SnapshotCaptureRetry.capture(
            named: "starved",
            makeViewController: { UIViewController() },
            capture: { _ in
                attempts += 1
                if attempts < 3 {
                    throw SnapshotRenderingError.settleStarved(
                        name: "starved",
                        phase: "content",
                        viewType: "probe",
                        passes: 1,
                        cap: 10,
                    )
                }
                return attempts
            },
            report: { _ in },
        )
        #expect(result == 3)
    }

    @Test(arguments: [
        SnapshotRenderingError.invalidSettleTimeoutMultiplier(value: "bad"),
        .measurementHookRequiresIntrinsicSizing(name: "probe"),
        .measurementReadinessTimedOut(name: "probe", budget: 1),
        .invalidMeasurementHookTimeout(name: "probe", budget: 0),
        .intrinsicHeightDidNotConverge(name: "probe", measuredHeights: [1, 2]),
        .fullContentSizeDidNotConverge(name: "probe", measuredSizes: [.zero]),
        .fullContentSizeExceedsLimit(
            name: "probe",
            pixelWidth: 100,
            pixelHeight: 100,
            maximumPixelDimension: 10,
            maximumPixelCount: 100,
        ),
        .pngEncodingFailed(name: "probe"),
        .missingCGImage(name: "probe"),
    ])
    func otherRenderingErrorsFailImmediately(error: SnapshotRenderingError) async {
        var attempts = 0
        await #expect(throws: error) {
            try await SnapshotCaptureRetry.capture(
                named: "probe",
                makeViewController: { UIViewController() },
                capture: { _ -> Int in
                    attempts += 1
                    throw error
                },
                report: { _ in Issue.record("An unrelated error must not trigger a retry") },
            )
        }
        #expect(attempts == 1)
    }

    @Test func arbitraryErrorIdentityIsPreserved() async {
        let original = SnapshotRetryProbeError()
        let error = await #expect(throws: SnapshotRetryProbeError.self) {
            try await SnapshotCaptureRetry.capture(
                named: "probe",
                makeViewController: { UIViewController() },
                capture: { _ -> Int in throw original },
                report: { _ in Issue.record("An unrelated error must not trigger a retry") },
            )
        }
        #expect(error === original)
    }

    @Test(arguments: [false, true])
    func cancellationPreventsAnotherAttempt(cancelBeforeCapture: Bool) async {
        var attempts = 0
        let task = Task { @MainActor in
            if cancelBeforeCapture { withUnsafeCurrentTask { $0?.cancel() } }
            return try await SnapshotCaptureRetry.capture(
                named: "cancelled",
                makeViewController: { UIViewController() },
                capture: { _ -> Int in
                    attempts += 1
                    throw snapshotRetryTimeout(attempt: attempts)
                },
                report: { _ in withUnsafeCurrentTask { $0?.cancel() } },
            )
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(attempts == (cancelBeforeCapture ? 0 : 1))
    }

    @Test func failedMeasurementRestoresHostStateBeforeAnotherAttempt() async throws {
        try waitFor { hostKeyWindow() != nil }
        let window = try #require(hostKeyWindow())
        let root = try #require(window.rootViewController)
        let windowSafeArea = window.safeAreaInsets
        let initialChildren = root.children
        let animationsWereEnabled = UIView.areAnimationsEnabled
        var controllers: [UIViewController] = []
        var attempts = 0
        let timing = SnapshotCaptureTiming(identifier: "cleanup", isEnabled: true)
        let policy = try SnapshotSettleTimeoutPolicy.parse(nil)
        let capture = try await SnapshotCaptureRetry.capture(
            named: "cleanup",
            makeViewController: {
                #expect(root.children == initialChildren)
                #expect(window.safeAreaInsets == windowSafeArea)
                #expect(UIView.areAnimationsEnabled == animationsWereEnabled)
                for previous in controllers {
                    #expect(previous.parent == nil)
                    #expect(previous.view.window == nil)
                    #expect(previous.traitCollection[SnapshotCaptureTrait.self] == false)
                }
                let controller = UIHostingController(rootView: Color.green.frame(
                    width: 40,
                    height: 40,
                ))
                controller.view.frame = CGRect(x: 0, y: 0, width: 40, height: 1)
                controllers.append(controller)
                return controller
            },
            capture: { controller in
                attempts += 1
                return try await renderSnapshotCapture(
                    of: controller,
                    named: "cleanup",
                    sizing: .intrinsic(width: 40, minimumHeight: 0),
                    safeAreaInsets: UIEdgeInsets(top: 3, left: 2, bottom: 1, right: 2),
                    isAccessibility: false,
                    measurementReadiness: .immediate,
                    onReadyToMeasure: {
                        #expect(controller.view.window != nil)
                        #expect(controller.traitCollection[SnapshotCaptureTrait.self])
                        #expect(UIView.areAnimationsEnabled == false)
                        if attempts < 3 { throw snapshotRetryTimeout(attempt: attempts) }
                    },
                    settle: .immediate,
                    onReadyToSnapshot: nil,
                    settleTimeoutPolicy: policy,
                    timing: timing,
                )
            },
            report: { _ in },
        )
        #expect(controllers.count == 3)
        #expect(controllers[0] !== controllers[1] && controllers[1] !== controllers[2])
        #expect(root.children == initialChildren)
        #expect(window.safeAreaInsets == windowSafeArea)
        #expect(UIView.areAnimationsEnabled == animationsWereEnabled)
        #expect(capture.pngData.isEmpty == false)
    }

    @Test func thrownCancellationIsNeverRetried() async {
        var attempts = 0
        await #expect(throws: CancellationError.self) {
            try await SnapshotCaptureRetry.capture(
                named: "cancelled",
                makeViewController: { UIViewController() },
                capture: { _ -> Int in
                    attempts += 1
                    throw CancellationError()
                },
                report: { _ in Issue.record("Cancellation must not trigger a retry") },
            )
        }
        #expect(attempts == 1)
    }
}
