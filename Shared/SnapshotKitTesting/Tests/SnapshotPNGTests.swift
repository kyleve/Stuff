@_spi(Testing) import SnapshotKitTesting
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

    @Test func appliesTabletLayoutTraitsToUIKitAndSwiftUI() async throws {
        try await expectAdaptiveLayoutTraits(
            .tabletPortrait,
            expected: AdaptiveTraitExpectation(
                interfaceIdiom: .pad,
                horizontalSizeClass: .regular,
                verticalSizeClass: .regular,
            ),
            captureName: "png-api-tablet-traits-probe",
        )
    }

    @Test func appliesPhoneLandscapeLayoutTraitsToUIKitAndSwiftUI() async throws {
        try await expectAdaptiveLayoutTraits(
            .phoneLandscape,
            expected: AdaptiveTraitExpectation(
                interfaceIdiom: .phone,
                horizontalSizeClass: .compact,
                verticalSizeClass: .compact,
            ),
            captureName: "png-api-phone-landscape-traits-probe",
        )
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
private func expectAdaptiveLayoutTraits(
    _ layoutTraits: SnapshotConfiguration.LayoutTraits,
    expected: AdaptiveTraitExpectation,
    captureName: String,
) async throws {
    let configuration = SnapshotConfiguration(
        layoutTraits: layoutTraits,
        device: SnapshotConfiguration.Frame(
            name: captureName,
            size: .fixed(CGSize(width: 100, height: 60)),
        ),
    )
    let png = try await captureSnapshotPNG(
        of: AdaptiveTraitProbe(expected: expected),
        configuration: configuration,
        named: captureName,
        sizing: .fixed,
        safeAreaInsets: .zero,
        measurementReadiness: .sameAsCapture,
        onReadyToMeasure: nil,
        settle: .immediate,
        onReadyToSnapshot: nil,
    )
    let image = try #require(UIImage(data: png.data, scale: png.scale))
    let swiftUITraits = image.probePixel(atUnitPoint: CGPoint(x: 0.25, y: 0.5))
    let uiKitTraits = image.probePixel(atUnitPoint: CGPoint(x: 0.75, y: 0.5))

    #expect(swiftUITraits.green > 0.5)
    #expect(swiftUITraits.red < 0.5)
    #expect(uiKitTraits.green > 0.5)
    #expect(uiKitTraits.red < 0.5)
}

private struct AdaptiveTraitExpectation {
    let interfaceIdiom: UIUserInterfaceIdiom
    let horizontalSizeClass: UIUserInterfaceSizeClass
    let verticalSizeClass: UIUserInterfaceSizeClass

    var swiftUIHorizontalSizeClass: UserInterfaceSizeClass {
        switch horizontalSizeClass {
            case .compact: .compact
            case .regular: .regular
            case .unspecified: .compact
            @unknown default: .compact
        }
    }

    var swiftUIVerticalSizeClass: UserInterfaceSizeClass {
        switch verticalSizeClass {
            case .compact: .compact
            case .regular: .regular
            case .unspecified: .compact
            @unknown default: .compact
        }
    }
}

private struct AdaptiveTraitProbe: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let expected: AdaptiveTraitExpectation

    var body: some View {
        HStack(spacing: 0) {
            let matches = horizontalSizeClass == expected.swiftUIHorizontalSizeClass
                && verticalSizeClass == expected.swiftUIVerticalSizeClass
            (matches ? Color.green : Color.red)
            UIKitAdaptiveTraitProbe(expected: expected)
        }
    }
}

private struct UIKitAdaptiveTraitProbe: UIViewRepresentable {
    let expected: AdaptiveTraitExpectation

    func makeUIView(context _: Context) -> UIKitAdaptiveTraitProbeView {
        UIKitAdaptiveTraitProbeView(expected: expected)
    }

    func updateUIView(_ view: UIKitAdaptiveTraitProbeView, context _: Context) {
        view.expected = expected
        view.setNeedsLayout()
    }
}

@MainActor
private final class UIKitAdaptiveTraitProbeView: UIView {
    var expected: AdaptiveTraitExpectation

    init(expected: AdaptiveTraitExpectation) {
        self.expected = expected
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let matches = traitCollection.userInterfaceIdiom == expected.interfaceIdiom
            && traitCollection.horizontalSizeClass == expected.horizontalSizeClass
            && traitCollection.verticalSizeClass == expected.verticalSizeClass
        backgroundColor = matches ? .green : .red
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
