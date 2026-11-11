@_spi(Testing) @testable import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct AccessibilitySnapshotViewControllerTests {
    @Test func preparationKeepsTheCaptureSizeUntilAnnotationsAreFinal() throws {
        let subject = ContainmentProbeController()
        subject.view.frame = CGRect(x: 0, y: 0, width: 100, height: 200)
        let capture = AccessibilitySnapshotViewController(wrapping: subject)
        let originalSize = capture.view.bounds.size
        try show(capture) { controller in
            controller.view.frame.size = originalSize
            controller.view.layoutIfNeeded()
            for _ in 0 ..< 2 {
                controller.parseAccessibility()
                #expect(controller.view.bounds.size == originalSize)
                #expect(subject.parent === controller)
            }
            controller.sizeToFitAnnotations()
            #expect(controller.view.bounds.width > originalSize.width
                || controller.view.bounds.height > originalSize.height)
        }
    }

    @Test(arguments: [
        CGSize(width: 100, height: 200),
        CGSize(width: 1984, height: 100),
        CGSize(width: 100, height: 1984),
    ])
    func untiledParsingKeepsTheSubjectParent(size: CGSize) async throws {
        // Annotation padding adds 16 points: equality at 2,000 does not tile.
        try await verifyContainment(size: size, expectedRemovals: 1)
    }

    @Test(arguments: [CGSize(width: 1985, height: 100), CGSize(width: 100, height: 1985)])
    func tiledParsingRestoresTheSubjectParent(size: CGSize) async throws {
        // At 2,001 padded points the upstream renderer adopts a temporary controller.
        try await verifyContainment(size: size, expectedRemovals: 3)
    }

    private func verifyContainment(size: CGSize, expectedRemovals: Int) async throws {
        let host = ContainmentProbeController()
        host.view.frame = CGRect(origin: .zero, size: size)
        _ = try await renderSnapshotImage(
            of: host,
            named: "accessibility-containment",
            safeAreaInsets: .zero,
            isAccessibility: true,
            settle: .settledAtLeast(minDuration: 0.01),
            onReadyToSnapshot: {
                #expect(host.view.window != nil)
                #expect(host.removals == 0)
            },
        )
        // Cleanup removes the subject once; tiling adds one removal per parse.
        #expect(host.removals == expectedRemovals)
        #expect(host.parent == nil)
        #expect(host.view.superview == nil)
    }

    @Test func annotationsStayAlignedWithCenteredNavigationContent() async throws {
        let configuration = SnapshotConfiguration(device: .iPad)
        let host = UIHostingController(rootView: CenteredAccessibilityFixture())
        configuration.applyTraits(to: host)
        host.view.frame = CGRect(x: 0, y: 0, width: 834, height: 1194)
        let image = try await renderSnapshotImage(
            of: host,
            named: "centered-accessibility-alignment",
            sizing: .intrinsic(width: 834, minimumHeight: 1194),
            safeAreaInsets: .zero,
            isAccessibility: true,
            settle: .settledAtLeast(minDuration: 0.25),
        )

        // Find the black card independently of the accessibility overlay. A shifted
        // overlay tints the white space just above or below the actual card.
        let x = (834.0 / 2 + 8) / image.size.width
        let darkRows = (0 ..< Int(image.size.height)).filter { row in
            let pixel = image.probePixel(atUnitPoint: CGPoint(
                x: x,
                y: CGFloat(row) / image.size.height,
            ))
            return max(pixel.red, pixel.green, pixel.blue) < 0.4
        }
        #expect(darkRows.count >= 110)
        let first = try #require(darkRows.first)
        let last = try #require(darkRows.last)
        for row in [first - 5, last + 5] {
            let pixel = image.probePixel(atUnitPoint: CGPoint(
                x: x,
                y: CGFloat(row) / image.size.height,
            ))
            #expect(abs(pixel.red - pixel.blue) < 0.03)
            #expect(min(pixel.red, pixel.green, pixel.blue) > 0.8)
        }
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
}

@MainActor
private final class ContainmentProbeController: UIViewController {
    var removals = 0

    override func loadView() {
        let button = UIButton(type: .system)
        button.setTitle("Action", for: .normal)
        view = button
    }

    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        if parent == nil { removals += 1 }
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

private struct CenteredAccessibilityFixture: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                Button {} label: {
                    Color.black.frame(width: 300, height: 120)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Centered card")
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.center, for: .alignment)
            .background(.white)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
