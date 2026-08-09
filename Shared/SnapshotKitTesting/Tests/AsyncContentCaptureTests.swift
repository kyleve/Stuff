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

    @Test func immediateMeasurementStillSettlesAsyncVisualStateBeforeCapture() async throws {
        try waitFor { hostKeyWindow() != nil }
        let host = UIHostingController(rootView: DelayedTaskProbeView())
        host.view.frame = CGRect(x: 0, y: 0, width: 100, height: 1)
        let image = try await renderSnapshotImage(
            of: host,
            named: "immediate-measurement-delayed-task-probe",
            sizing: .intrinsic(width: 100, minimumHeight: 0),
            safeAreaInsets: .zero,
            measurementReadiness: .immediate,
            settle: .settled,
        )
        let center = image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5))
        #expect(image.size.height == 100)
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

private struct TaskProbeView: View {
    @State private var taskFired = false

    var body: some View {
        (taskFired ? Color.green : Color.red)
            .frame(width: 100, height: 100)
            .task { taskFired = true }
    }
}

private struct DelayedTaskProbeView: View {
    @State private var taskFired = false

    var body: some View {
        (taskFired ? Color.green : Color.red)
            .frame(width: 100, height: 100)
            .task {
                try? await Task.sleep(for: .milliseconds(100))
                taskFired = true
            }
    }
}
