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

    @Test func immediateMeasurementStillRunsFinalCaptureSettle() async throws {
        try waitFor { hostKeyWindow() != nil }
        let host = UIHostingController(rootView: Color.green.frame(width: 100, height: 100))
        host.view.frame = CGRect(x: 0, y: 0, width: 100, height: 1)
        let timing = SnapshotCaptureTiming(
            identifier: "immediate-measurement-settle-probe",
            isEnabled: true,
            sizing: .intrinsic(width: 100, minimumHeight: 0),
            measurementReadiness: .immediate,
            captureSettle: .settled,
        )
        let capture = try await renderSnapshotCapture(
            of: host,
            named: "immediate-measurement-settle-probe",
            sizing: .intrinsic(width: 100, minimumHeight: 0),
            safeAreaInsets: .zero,
            isAccessibility: false,
            measurementReadiness: .immediate,
            onReadyToMeasure: nil,
            settle: .settled,
            onReadyToSnapshot: nil,
            settleTimeoutPolicy: SnapshotSettleTimeoutPolicy.parse(nil),
            timing: timing,
        )
        let line = try #require(timing.line())
        let decoded = try JSONDecoder().decode(
            SettleTiming.self,
            from: Data(line.utf8),
        )
        let center = capture.image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5))
        #expect(capture.image.size.height == 100)
        #expect(decoded.settlePasses >= 3)
        #expect(center.green > 0.5)
        #expect(center.red < 0.5)
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
    let settlePasses: Int
}

private struct TaskProbeView: View {
    @State private var taskFired = false

    var body: some View {
        (taskFired ? Color.green : Color.red)
            .frame(width: 100, height: 100)
            .task { taskFired = true }
    }
}
