import BroadwayCore
import BroadwayTesting
import BroadwayUI
import SwiftUI
import Testing
import UIKit

@MainActor
struct BContextEnvironmentTests {
    private enum ProbeTheme: String, BTheme {
        static let defaultValue: Self = .a
        case a, b
    }

    @Test("A SwiftUI-set context takes precedence and reads back synchronously")
    func swiftUISetContextWins() {
        var context = BContext(traits: .system)
        context.themes[ProbeTheme.self] = .b

        var env = EnvironmentValues()
        env.bContext = context

        #expect(env.bContext == context)
        #expect(env.bContext.themes[ProbeTheme.self] == .b)
    }

    @Test("bContext falls back to the default when no SwiftUI context is set")
    func fallsBackToDefault() {
        #expect(EnvironmentValues().bContext == BContextTrait.defaultValue)
    }

    @Test("Transforming bContext (as bTraitOverrides does) round-trips via the SwiftUI value")
    func transformRoundTrips() {
        var env = EnvironmentValues()
        var context = env.bContext
        context.traitOverrides.mode = .dark
        env.bContext = context

        #expect(env.bContext.traits.mode == .dark)
    }
}

// MARK: - SwiftUI → UIKit mirroring

private enum MirrorTheme: String, BTheme {
    static let defaultValue: Self = .a
    case a, b
}

private final class MirrorBox {
    var value: BContext?
}

/// A UIKit view controller (hosted below SwiftUI via a representable) that
/// records the `BContext` it inherits from its trait collection.
private final class CapturingViewController: UIViewController {
    let box: MirrorBox

    init(box: MirrorBox) {
        self.box = box
        super.init(nibName: nil, bundle: nil)
        registerForTraitChanges([BContextTrait.self]) { (vc: CapturingViewController, _) in
            vc.box.value = vc.traitCollection.bContext
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        box.value = traitCollection.bContext
    }
}

private struct CapturingRepresentable: UIViewControllerRepresentable {
    let box: MirrorBox

    func makeUIViewController(context _: Context) -> CapturingViewController {
        CapturingViewController(box: box)
    }

    func updateUIViewController(_: CapturingViewController, context _: Context) {}
}

@MainActor
struct BContextSwiftUIToUIKitTests {
    @Test("A SwiftUI-set context is mirrored into nested UIKit views")
    func mirrorsToNestedUIKit() throws {
        var context = BContext(traits: .system)
        context.themes[MirrorTheme.self] = .b

        let box = MirrorBox()
        let host = UIHostingController(
            rootView: CapturingRepresentable(box: box).environment(\.bContext, context),
        )

        try show(host) { _ in
            // UIKit picks up the mirrored trait on its own layout/trait pass, so
            // poll rather than assuming it's present on first appearance.
            try waitFor { box.value?.themes[MirrorTheme.self] == .b }
        }
    }
}
