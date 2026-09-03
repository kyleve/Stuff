@_spi(Testing) import SnapshotKitTesting
import TestHostSupport
import Testing
import UIKit

@MainActor
struct AccessibilitySnapshotViewControllerTests {
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
