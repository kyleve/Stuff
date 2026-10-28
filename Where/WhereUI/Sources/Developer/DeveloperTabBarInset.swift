import SwiftUI

extension View {
    /// Report the logged-in tab bar's height up the tree so the DEBUG developer
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

    /// Carries the floating tab bar's height from `MainTabs` up to ``RootView``,
    /// which hands it to the sibling ``DeveloperOverlay``.
    ///
    /// A tab's content receives a bottom safe-area inset that spans the home
    /// indicator *and* the floating tab bar; subtracting the window's own bottom
    /// inset (the home indicator alone) leaves just the bar's height. Reduced with
    /// `max` so whichever tab is on screen wins. When logged out there's no tab
    /// bar in the tree, so the value stays at its `0` default.
    struct DeveloperTabBarInsetKey: PreferenceKey {
        static let defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
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
        func body(content: Content) -> some View {
            content.background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: DeveloperTabBarInsetKey.self,
                        value: max(0, proxy.safeAreaInsets.bottom - Self.windowBottomInset),
                    )
                }
            }
        }

        /// The window's own bottom safe-area inset (the home indicator), which the
        /// tab content's inset sits on top of. Read from the key window because the
        /// reporter lives inside the tab bar's inset and can't see the bare window
        /// inset itself.
        @MainActor private static var windowBottomInset: CGFloat {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }?
                .safeAreaInsets.bottom ?? 0
        }
    }
#endif
