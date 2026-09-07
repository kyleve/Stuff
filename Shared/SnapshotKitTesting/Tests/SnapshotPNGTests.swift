import SnapshotKitTesting
import SwiftUI
import Testing
import UIKit

@MainActor
struct SnapshotPNGTests {
    @Test func returnsPNGBytesAndPointAndPixelDimensions() async throws {
        let configuration = SnapshotConfiguration(
            device: SnapshotConfiguration.Frame(
                name: "probe",
                size: .fixed(CGSize(width: 80, height: 60)),
            ),
        )

        let png = try await captureSnapshotPNG(
            of: Color.red,
            configuration: configuration,
            named: "png-api-fixed-probe",
            sizing: .fixed,
            safeAreaInsets: .zero,
            measurementReadiness: .sameAsCapture,
            onReadyToMeasure: nil,
            settle: .immediate,
            onReadyToSnapshot: nil,
        )

        #expect(png.data.isEmpty == false)
        #expect(png.pointSize == CGSize(width: 80, height: 60))
        #expect(png.pixelSize.width == png.pointSize.width * png.scale)
        #expect(png.pixelSize.height == png.pointSize.height * png.scale)
    }

    @Test func runsReadinessHooksThroughTheSharedPipeline() async throws {
        var measurementHookRan = false
        var finalHookRan = false
        let configuration = SnapshotConfiguration(
            device: SnapshotConfiguration.Frame(
                name: "intrinsic-probe",
                size: .intrinsic(maxWidth: 100),
            ),
        )

        _ = try await captureSnapshotPNG(
            of: Color.blue.frame(height: 40),
            configuration: configuration,
            named: "png-api-hooks-probe",
            sizing: .intrinsic(width: 100, minimumHeight: 0),
            safeAreaInsets: .zero,
            measurementReadiness: .immediate,
            onReadyToMeasure: { measurementHookRan = true },
            settle: .immediate,
            onReadyToSnapshot: { finalHookRan = true },
        )

        #expect(measurementHookRan)
        #expect(finalHookRan)
    }

    @Test func capturesFullHeightContent() async throws {
        let content = ScrollView {
            VStack(spacing: 0) {
                Color.red.frame(height: 100)
                Color.blue.frame(height: 100)
            }
        }
        let configuration = SnapshotConfiguration(
            device: .fullContent(name: "full-height-probe", width: 100, minimumHeight: 60),
        )

        let png = try await captureSnapshotPNG(
            of: content,
            configuration: configuration,
            named: "png-api-full-height-probe",
            sizing: .intrinsic(width: 100, minimumHeight: 60),
            safeAreaInsets: .zero,
            measurementReadiness: .immediate,
            onReadyToMeasure: nil,
            settle: .immediate,
            onReadyToSnapshot: nil,
        )

        #expect(png.pointSize == CGSize(width: 100, height: 200))
    }

    @Test func capturesTwoAxisFullContent() async throws {
        let content = ScrollView([.horizontal, .vertical]) {
            Color.green.frame(width: 180, height: 160)
        }
        let minimumSize = CGSize(width: 80, height: 60)
        let configuration = SnapshotConfiguration(
            device: .fullContent2D(name: "two-axis-probe", minimumSize: minimumSize),
        )

        let png = try await captureSnapshotPNG(
            of: content,
            configuration: configuration,
            named: "png-api-two-axis-probe",
            sizing: .fullContent2D(minimumSize: minimumSize),
            safeAreaInsets: .zero,
            measurementReadiness: .immediate,
            onReadyToMeasure: nil,
            settle: .immediate,
            onReadyToSnapshot: nil,
        )

        #expect(png.pointSize == CGSize(width: 180, height: 160))
    }

    @Test func capturesAccessibilityAnnotations() async throws {
        let configuration = SnapshotConfiguration(
            device: SnapshotConfiguration.Frame(
                name: "accessibility-probe",
                size: .fixed(CGSize(width: 240, height: 160)),
            ),
            snapshotType: .accessibility,
        )

        let png = try await captureSnapshotPNG(
            of: Text("Atlas item").accessibilityLabel("Atlas accessibility item"),
            configuration: configuration,
            named: "png-api-accessibility-probe",
            sizing: .fixed,
            safeAreaInsets: .zero,
            measurementReadiness: .sameAsCapture,
            onReadyToMeasure: nil,
            settle: .immediate,
            onReadyToSnapshot: nil,
        )

        #expect(png.data.isEmpty == false)
        #expect(png.pointSize.width >= 240)
        #expect(png.pointSize.height >= 160)
    }

    @Test func cancelledQueuedCaptureDoesNotRunMeasurementHook() async throws {
        let probe = QueuedCaptureCancellationProbe()
        let fixedConfiguration = SnapshotConfiguration(
            device: SnapshotConfiguration.Frame(
                name: "queued-cancellation-holder",
                size: .fixed(CGSize(width: 80, height: 60)),
            ),
        )
        let firstCapture = Task { @MainActor in
            try await captureSnapshotPNG(
                of: Color.red,
                configuration: fixedConfiguration,
                named: "queued-cancellation-holder",
                sizing: .fixed,
                safeAreaInsets: .zero,
                measurementReadiness: .sameAsCapture,
                onReadyToMeasure: nil,
                settle: .immediate,
                onReadyToSnapshot: {
                    probe.firstCaptureStarted = true
                    while probe.canFinishFirstCapture == false {
                        await Task.yield()
                    }
                },
            )
        }
        while probe.firstCaptureStarted == false {
            await Task.yield()
        }

        let intrinsicConfiguration = SnapshotConfiguration(
            device: SnapshotConfiguration.Frame(
                name: "queued-cancellation-waiter",
                size: .intrinsic(maxWidth: 80),
            ),
        )
        let queuedCapture = Task { @MainActor in
            probe.queuedCaptureStarted = true
            return try await captureSnapshotPNG(
                of: Color.blue.frame(height: 60).onAppear {
                    probe.queuedContentAppeared = true
                },
                configuration: intrinsicConfiguration,
                named: "queued-cancellation-waiter",
                sizing: .intrinsic(width: 80, minimumHeight: 0),
                safeAreaInsets: .zero,
                measurementReadiness: .immediate,
                onReadyToMeasure: { probe.measurementHookRan = true },
                settle: .immediate,
                onReadyToSnapshot: nil,
            )
        }
        while probe.queuedCaptureStarted == false {
            await Task.yield()
        }

        queuedCapture.cancel()
        probe.canFinishFirstCapture = true
        _ = try await firstCapture.value
        await #expect(throws: CancellationError.self) {
            try await queuedCapture.value
        }
        #expect(probe.measurementHookRan == false)
        #expect(probe.queuedContentAppeared == false)
    }

    @Test func propagatesSettleFailures() async throws {
        let configuration = SnapshotConfiguration(
            device: SnapshotConfiguration.Frame(
                name: "moving-probe",
                size: .fixed(CGSize(width: 80, height: 60)),
            ),
        )

        let error = await #expect(throws: SnapshotRenderingError.self) {
            try await captureSnapshotPNG(
                of: NonSettlingPNGView(),
                configuration: configuration,
                named: "png-api-moving-probe",
                sizing: .fixed,
                safeAreaInsets: .zero,
                measurementReadiness: .sameAsCapture,
                onReadyToMeasure: nil,
                settle: .settled,
                onReadyToSnapshot: nil,
            )
        }
        guard case let .settleTimedOut(name, phase, _, _) = error else {
            Issue.record("Expected a settle timeout, got \(String(describing: error)).")
            return
        }
        #expect(name == "png-api-moving-probe")
        #expect(phase == "content")
    }
}

@MainActor
private final class QueuedCaptureCancellationProbe {
    var firstCaptureStarted = false
    var canFinishFirstCapture = false
    var queuedCaptureStarted = false
    var measurementHookRan = false
    var queuedContentAppeared = false
}

private struct NonSettlingPNGView: View {
    @State private var isRed = false

    var body: some View {
        (isRed ? Color.red : Color.blue)
            .task {
                while Task.isCancelled == false {
                    isRed.toggle()
                    do {
                        try await Task.sleep(for: .milliseconds(40))
                    } catch is CancellationError {
                        return
                    } catch {
                        Issue.record(error)
                        return
                    }
                }
            }
    }
}
