@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct AccessibilitySnapshotViewControllerTests {
    @Test(arguments: [800.0, 2400.0], [false, true])
    func annotatesSwiftUIFormFramesAcrossTheTileBoundary(
        height: CGFloat,
        raisedFloor: Bool,
    ) async throws {
        try waitFor { hostKeyWindow() != nil }
        let host = UIHostingController(rootView: NavigationStack {
            Form {
                Color.white
                    .frame(height: height)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Accessible form content")
            }
            .navigationTitle("Accessible form")
        })
        let image = try await renderSnapshotImage(
            of: host,
            named: "accessibility-form-frames",
            sizing: .intrinsic(width: 402, minimumHeight: 0),
            safeAreaInsets: .zero,
            isAccessibility: true,
            settle: raisedFloor ? .settledAtLeast(minDuration: 0.01) : .settled,
        )

        // The source image is monochrome. Color in the middle of the content pane comes
        // from the accessibility region overlay, rather than the separate legend.
        let region = image.probePixel(atUnitPoint: CGPoint(x: 100 / image.size.width, y: 0.5))
        #expect(abs(region.red - region.green) > 0.05 || abs(region.green - region.blue) > 0.05)
    }

    @Test func reparsesAfterContentEntersTheWindow() async throws {
        try waitFor { hostKeyWindow() != nil }
        let content = WindowAttachmentProbeView(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        let host = UIViewController()
        host.view = content

        let image = try await renderSnapshotImage(
            of: host,
            named: "accessibility-window-attachment-probe",
            safeAreaInsets: .zero,
            isAccessibility: true,
            settle: .settledAtLeast(minDuration: 0.01),
        )

        let contentCenter = image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5))
        #expect(contentCenter.red > 0.5)
        #expect(contentCenter.green > 0.5)
        #expect(contentCenter.blue > 0.5)
    }

    @Test func keepsTheLiveSourceHostedForTheReadinessHook() async throws {
        try waitFor { hostKeyWindow() != nil }
        let host = UIViewController()
        host.view = WindowAttachmentProbeView(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        var hookRan = false
        _ = try await renderSnapshotImage(
            of: host,
            named: "accessibility-live-readiness",
            safeAreaInsets: .zero,
            isAccessibility: true,
            onReadyToSnapshot: {
                hookRan = true
                #expect(host.view.window === hostKeyWindow())
                #expect(host.parent != nil)
            },
        )
        #expect(hookRan)
    }
}

@MainActor
private final class WindowAttachmentProbeView: UIView {
    private var scheduledUpdate = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black

        let accessibleElement = UIView(frame: CGRect(x: 8, y: 8, width: 20, height: 20))
        accessibleElement.isAccessibilityElement = true
        accessibleElement.accessibilityLabel = "Window attachment probe"
        addSubview(accessibleElement)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, scheduledUpdate == false else { return }
        scheduledUpdate = true
        DispatchQueue.main.async { [weak self] in
            self?.backgroundColor = .white
        }
    }
}
