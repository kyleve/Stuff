import SwiftUI

extension View {
    /// Report the logged-in tab bar's edge insets up the tree so the DEBUG developer
    /// overlay can rest its collapsed button clear of the floating tab bar,
    /// measured from the live UI instead of a hardcoded guess. Applied to each
    /// tab's content in `MainTabs`. A no-op in release, where the overlay (and the
    /// preference it feeds) don't exist.
    func reportingDeveloperTabBarInset() -> some View {
        #if DEBUG
            modifier(DeveloperTabBarInsetReporter())
        #else
            self
        #endif
    }
}

#if DEBUG
    import UIKit

    /// Carries the floating tab bar's edge insets from `MainTabs` up to ``RootView``,
    /// which hands it to the sibling ``DeveloperOverlay``.
    ///
    /// Subtract the attached window's system insets independently on every edge.
    /// Reduce each edge with `max` so the visible tab wins. Logged-out scenes report zero.
    struct DeveloperTabBarInsetKey: PreferenceKey {
        static let defaultValue = EdgeInsets()

        static func reduce(value: inout EdgeInsets, nextValue: () -> EdgeInsets) {
            let next = nextValue()
            value.top = max(value.top, next.top)
            value.leading = max(value.leading, next.leading)
            value.bottom = max(value.bottom, next.bottom)
            value.trailing = max(value.trailing, next.trailing)
        }
    }

    /// Carries the floating developer window's footprint — the safe-area inset it
    /// occupies on each edge it's docked to — from ``DeveloperOverlay`` up to
    /// ``RootView``, which feeds it back into the app content's safe area
    /// (`safeAreaPadding`) so screens *behind* the non-modal HUD can scroll clear
    /// of it. The mirror image of ``DeveloperTabBarInsetKey`` (which flows the tab
    /// bar's height the other way). Zero in the collapsed and full-screen states.
    struct DeveloperOverlayInsetKey: PreferenceKey {
        static let defaultValue = EdgeInsets()

        static func reduce(value: inout EdgeInsets, nextValue: () -> EdgeInsets) {
            let next = nextValue()
            value.top = max(value.top, next.top)
            value.bottom = max(value.bottom, next.bottom)
            value.leading = max(value.leading, next.leading)
            value.trailing = max(value.trailing, next.trailing)
        }
    }

    private struct DeveloperTabBarInsetReporter: ViewModifier {
        @State private var windowInsets = UIEdgeInsets.zero
        /// The attached window supplies physical insets; convert them using the live direction.
        @Environment(\.layoutDirection) private var layoutDirection

        func body(content: Content) -> some View {
            content.background {
                GeometryReader { proxy in
                    Color.clear
                        .background {
                            DeveloperWindowInsetsReader { windowInsets = $0 }
                        }
                        .preference(
                            key: DeveloperTabBarInsetKey.self,
                            value: DeveloperBarInsets.additional(
                                content: proxy.safeAreaInsets,
                                window: windowInsets,
                                direction: layoutDirection,
                            ),
                        )
                }
            }
        }
    }

    /// Subtract only this host window's system edges, including a side-mounted status bar.
    enum DeveloperBarInsets {
        static func additional(
            content: EdgeInsets,
            window: UIEdgeInsets,
            direction: LayoutDirection,
        ) -> EdgeInsets {
            EdgeInsets(
                top: max(0, content.top - window.top),
                leading: max(
                    0,
                    content.leading - (direction == .leftToRight ? window.left : window.right),
                ),
                bottom: max(0, content.bottom - window.bottom),
                trailing: max(
                    0,
                    content.trailing - (direction == .leftToRight ? window.right : window.left),
                ),
            )
        }
    }

    /// Reads the window containing this reporter. It never searches other scenes or screens.
    private struct DeveloperWindowInsetsReader: UIViewRepresentable {
        let changed: (UIEdgeInsets) -> Void

        func makeUIView(context _: Context) -> InsetView {
            InsetView()
        }

        func updateUIView(_ view: InsetView, context _: Context) {
            view.changed = changed
            view.scheduleUpdate()
        }

        static func dismantleUIView(_ view: InsetView, coordinator _: Void) {
            view.pending?.cancel()
            view.changed = nil
        }

        final class InsetView: UIView {
            var changed: ((UIEdgeInsets) -> Void)?
            var pending: Task<Void, Never>?
            private var reported: UIEdgeInsets?

            override func didMoveToWindow() {
                super.didMoveToWindow()
                scheduleUpdate()
            }

            override func safeAreaInsetsDidChange() {
                super.safeAreaInsetsDidChange()
                scheduleUpdate()
            }

            override func layoutSubviews() {
                super.layoutSubviews()
                scheduleUpdate()
            }

            func scheduleUpdate() {
                guard let insets = window?.safeAreaInsets, reported != insets else { return }
                pending?.cancel()
                pending = Task { @MainActor [weak self] in
                    guard !Task.isCancelled, let self, window != nil else { return }
                    reported = insets
                    changed?(insets)
                }
            }
        }
    }
#endif
