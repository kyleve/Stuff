import Foundation
@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

/// Regression guard for `.task`-driven content: SwiftUI `.task` bodies are
/// main-actor concurrency jobs, which a synchronous run-loop pump can never
/// interleave (the main queue is non-reentrant) — the pipeline must genuinely
/// suspend while settling or content computed in `.task` (CalendarView's month
/// grid, TypewriterText's reveal) snapshots as its placeholder. The probe view
/// renders red until its `.task` flips it green; a green capture proves the
/// pipeline let the task run.
@MainActor
struct AsyncContentCaptureTests {
    @Test func capturesContentLoadedByATask() async throws {
        try waitFor { hostKeyWindow() != nil }
        let host = UIHostingController(rootView: TaskProbeView())
        host.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let image = try await renderSnapshotImage(
            of: host,
            named: "task-probe",
            safeAreaInsets: .zero,
        )
        let center = image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5))
        #expect(center.green > 0.5)
        #expect(center.red < 0.5)
    }

    enum MeasuredCapture: CaseIterable {
        case standard
        case afterMeasurement
        case afterSettledMeasurement
        case nativeInsetChange
        case syntheticInsetChange
        case prepareForCapture
        case onReadyToSnapshot
        case raisedFloor
        case accessibility
        case fixed
    }

    @Test(arguments: MeasuredCapture.allCases)
    func captureAfterMeasurementHonorsReadiness(_ scenario: MeasuredCapture) async throws {
        try waitFor { hostKeyWindow() != nil }
        let host = MountCountingHost(rootView: Color.green.frame(width: 100, height: 100))
        host.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let timing = SnapshotCaptureTiming(identifier: "measured-capture", isEnabled: true)
        let changesInsets = scenario == .nativeInsetChange || scenario == .syntheticInsetChange
        let measurementHook: (@MainActor @Sendable () async throws -> Void)? = if scenario ==
            .afterSettledMeasurement
        {
            { #expect(host.view.window != nil) }
        } else if changesInsets {
            { try Self.changeTopInset(of: host) }
        } else {
            nil
        }
        let sizing: SnapshotSizing = scenario == .fixed ? .fixed : .intrinsic(
            width: 100,
            minimumHeight: 0,
        )
        let readiness: SnapshotMeasurementReadiness = scenario == .afterSettledMeasurement ?
            .sameAsCapture : .immediate
        let settle: SnapshotSettle = scenario == .raisedFloor ? .settledAtLeast(minDuration: 0.25) :
            .settled
        var prepare: (@MainActor @Sendable () async throws -> Void)?
        var ready: (@MainActor @Sendable () async -> Void)?
        if scenario == .prepareForCapture {
            prepare = { #expect(host.view.window != nil) }
        }
        if scenario == .onReadyToSnapshot {
            ready = { #expect(host.view.window != nil) }
        }
        let timeoutPolicy = try SnapshotSettleTimeoutPolicy.parse(nil)
        let capture = try await renderSnapshotCapture(
            of: host,
            named: "measured-capture",
            sizing: sizing,
            safeAreaInsets: .zero,
            scenePolicy: scenario == .nativeInsetChange ? .retained : .automatic,
            isAccessibility: scenario == .accessibility,
            measurementReadiness: readiness,
            onReadyToMeasure: measurementHook,
            settle: settle,
            captureAfterMeasurement: scenario != .standard,
            prepareForCapture: prepare,
            onReadyToSnapshot: ready,
            settleTimeoutPolicy: timeoutPolicy,
            timing: timing,
        )
        let line = try #require(timing.line())
        let decoded = try JSONDecoder().decode(
            SettleTiming.self,
            from: Data(line.utf8),
        )
        let retained = scenario == .afterMeasurement || scenario == .afterSettledMeasurement
            || changesInsets
        #expect(decoded.captureMode == (retained ? "afterMeasurement" : "standard"))
        if scenario == .afterMeasurement || scenario == .syntheticInsetChange {
            #expect(decoded.settlePasses == 0)
        } else {
            #expect(decoded.settlePasses >= 3)
        }
        let expectedMounts = retained || scenario == .fixed ? 1 : 2
        #expect(host.mountCount == expectedMounts)
        #expect(host.parent == nil)
        #expect(host.view.window == nil)
        if scenario != .accessibility {
            let center = capture.image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5))
            // The measurement hook adds 20 points above the 100-point view.
            let expectedHeight: CGFloat = changesInsets ? 120 : 100
            #expect(capture.image.size == CGSize(width: 100, height: expectedHeight))
            #expect(center.green > 0.5 && center.red < 0.5)
        }
    }

    /// Simulates native chrome changing clearance after the initial measurement layout.
    private static func changeTopInset(of host: UIViewController) throws {
        let root = try #require(host.view.window?.rootViewController)
        root.additionalSafeAreaInsets.top += 20
        root.view.setNeedsLayout()
        root.view.layoutIfNeeded()
        #expect(root.view.safeAreaInsets.top > 0)
    }

    @Test func immediateMeasurementDoesNotShortenRaisedCaptureFloor() async throws {
        try waitFor { hostKeyWindow() != nil }
        let host = UIHostingController(rootView: Color.green.frame(width: 100, height: 100))
        host.view.frame = CGRect(x: 0, y: 0, width: 100, height: 1)
        let clock = ContinuousClock()
        let began = clock.now
        _ = try await renderSnapshotImage(
            of: host,
            named: "immediate-measurement-raised-floor-probe",
            sizing: .intrinsic(width: 100, minimumHeight: 0),
            safeAreaInsets: .zero,
            measurementReadiness: .immediate,
            settle: .settledAtLeast(minDuration: 0.2),
        )
        #expect(began.duration(to: clock.now) >= .milliseconds(190))
    }
}

private struct SettleTiming: Decodable {
    let captureMode: String
    let settlePasses: Int
}

private final class MountCountingHost<Content: View>: UIHostingController<Content> {
    private(set) var mountCount = 0

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent != nil {
            mountCount += 1
        }
    }
}

private struct TaskProbeView: View {
    @State private var taskFired = false

    var body: some View {
        (taskFired ? Color.green : Color.red)
            .frame(width: 100, height: 100)
            .task { taskFired = true }
    }
}
