import SnapshotKit
@_spi(Testing) @testable import SnapshotKitTesting
import SwiftUI
import Testing

@MainActor
struct ImmediateComponentCaptureTests {
    @Test func measuresAndDrawsTheConfiguredComponentOnOneMount() async throws {
        try await SnapshotCaptureLock.withHost { window in
            var appearances = 0
            let configuration = SnapshotConfiguration(
                colorScheme: .dark,
                device: .init(name: "", size: .intrinsic(maxWidth: 71)),
            )
            let controller = makeHostingController(
                for: ComponentProbe().onAppear { appearances += 1 },
                configuration: configuration,
                hostWidth: window.bounds.width,
            )
            let timing = SnapshotCaptureTiming(identifier: "component", isEnabled: true)
            let output = try await captureImmediateComponentIfPossible(
                of: controller,
                in: window,
                configuration: configuration,
                named: "component",
                timing: timing,
                timeoutPolicy: .init(multiplier: 1),
            )
            let capture = try #require(output)
            #expect(appearances == 1)
            #expect(controller.parent == nil)
            #expect(controller.view.superview == nil)
            #expect(capture.image.size == CGSize(width: 71, height: 23))
            #expect(capture.image.scale == window.traitCollection.displayScale)
            let center = capture.image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5))
            #expect(center.green > 0.5 && center.red < 0.5)
            #expect(timing.captureMode == .immediateComponent)
        }
    }

    @Test func returnsAnOversizedComponentToTheTiledRenderer() async throws {
        try await SnapshotCaptureLock.withHost { window in
            let configuration = SnapshotConfiguration(device: .component)
            let controller = makeHostingController(
                for: Color.green.frame(height: 2001),
                configuration: configuration,
                hostWidth: window.bounds.width,
            )
            let initialFrame = controller.view.frame
            let initialRegions = controller.safeAreaRegions
            let root = try #require(window.rootViewController)
            let initialChildren = root.children
            let timing = SnapshotCaptureTiming(identifier: "tall-component", isEnabled: true)
            let capture = try await captureImmediateComponentIfPossible(
                of: controller,
                in: window,
                configuration: configuration,
                named: "tall-component",
                timing: timing,
                timeoutPolicy: .init(multiplier: 1),
            )
            #expect(capture == nil)
            #expect(timing.captureMode == .standard)
            #expect(root.children == initialChildren)
            #expect(controller.view.superview == nil)
            #expect(controller.view.frame == initialFrame)
            #expect(controller.safeAreaRegions == initialRegions)
        }
    }

    @Test(arguments: [CGFloat(60), CGFloat(240)])
    func capturesCompleteScrollContentWhenTheIdealHeightIsBounded(
        _ idealHeight: CGFloat,
    ) async throws {
        let result = try await captureConfiguredSnapshot(
            of: BoundedScrollProbe(idealHeight: idealHeight),
            configuration: SnapshotConfiguration(device: .init(
                name: "",
                size: .intrinsic(maxWidth: 80),
            )),
            named: "bounded-component",
            measurementReadiness: .immediate,
            onReadyToMeasure: nil,
            measurementHookTimeout: nil,
            settle: .immediate,
            onReadyToSnapshot: nil,
            captureMode: .immediateComponent,
            timeoutPolicy: .init(multiplier: 1),
        )
        let image = result.capture.image
        #expect(result.timing.captureMode == .standard)
        #expect(image.size == CGSize(width: 80, height: 240))
        let first = image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.05))
        let last = image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.95))
        #expect(first.red > 0.5 && first.blue < 0.5)
        #expect(last.blue > 0.5 && last.red < 0.5)
    }
}

private struct ComponentProbe: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot
    @State private var taskStarted = false

    var body: some View {
        (isCapturingSnapshot && colorScheme == .dark ? Color.green : Color.red)
            .frame(height: taskStarted ? 23 : 11)
            .task { taskStarted = true }
    }
}

/// A native scroll view can fill an assigned viewport while reporting a shorter ideal height.
private struct BoundedScrollProbe: UIViewRepresentable {
    let idealHeight: CGFloat

    func makeUIView(context _: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.contentInsetAdjustmentBehavior = .never
        let first = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 100))
        first.backgroundColor = .red
        let last = UIView(frame: CGRect(x: 0, y: 100, width: 80, height: 140))
        last.backgroundColor = .blue
        scroll.addSubview(first)
        scroll.addSubview(last)
        scroll.contentSize = CGSize(width: 80, height: 240)
        scroll.contentOffset.y = 100
        return scroll
    }

    func updateUIView(_: UIScrollView, context _: Context) {}

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView _: UIScrollView,
        context _: Context,
    ) -> CGSize? {
        let height = proposal.height ?? idealHeight
        // The capture asks for the ideal height with an unbounded proposal.
        // During layout the scroll view fills its assigned viewport.
        return CGSize(width: 80, height: height < tileDimension ? height : idealHeight)
    }
}
