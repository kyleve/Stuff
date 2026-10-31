@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct AccessibilitySnapshotViewControllerTests {
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
