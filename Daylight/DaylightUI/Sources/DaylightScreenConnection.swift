import SwiftUI
import UIKit

/// Supplies the actual hosting window's screen to the capture model.
struct DaylightScreenConnection: UIViewRepresentable {
    let connect: @MainActor (UIScreen) -> Void
    func makeUIView(context _: Context) -> ScreenView {
        ScreenView(connect: connect)
    }

    func updateUIView(_: ScreenView, context _: Context) {}
    final class ScreenView: UIView {
        let connect: @MainActor (UIScreen) -> Void
        init(connect: @escaping @MainActor (UIScreen) -> Void) {
            self.connect = connect
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable) required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let screen = window?.windowScene?.screen { connect(screen) }
        }
    }
}

#if DEBUG
    #Preview { DaylightScreenConnection(connect: { _ in }) }
#endif
