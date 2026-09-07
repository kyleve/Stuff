import AppKit
import SwiftUI

/// Reports whether the hosting window is actually on screen — visible and
/// not fully occluded — into a binding. Ordered-out windows keep their
/// SwiftUI hierarchy alive (`.task` loops keep running; verified
/// empirically), so views doing periodic work need this signal to pause.
///
/// Use as a `.background`; the represented view has no size or appearance.
struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context _: Context) -> ReaderView {
        ReaderView { visible in
            if visible != isVisible {
                isVisible = visible
            }
        }
    }

    func updateNSView(_: ReaderView, context _: Context) {}

    final class ReaderView: NSView {
        private let onChange: (Bool) -> Void
        private var observer: NSObjectProtocol?

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("not used")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main,
            ) { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                self?.onChange(window.occlusionState.contains(.visible))
            }
            onChange(window.occlusionState.contains(.visible))
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
