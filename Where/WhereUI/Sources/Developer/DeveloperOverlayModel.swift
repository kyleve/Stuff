#if DEBUG
    import SwiftUI

    /// State for the floating developer overlay: how it's currently presented and
    /// which corner the collapsed button rests in.
    ///
    /// The presentation is a single enum rather than a set of `Bool`s so the
    /// illegal combinations (e.g. "floating *and* full screen") can't be spelled.
    @MainActor
    @Observable
    final class DeveloperOverlayModel {
        /// How the overlay is shown. Collapsed is the resting state (a small
        /// button); `floating` is the Picture-in-Picture panel; `fullScreen`
        /// covers the app.
        enum Presentation: Equatable {
            case collapsed
            case floating
            case fullScreen
        }

        /// The resting corner of the collapsed button. Snapped to on drag end, so
        /// the button always parks in a predictable spot rather than mid-screen.
        enum Corner: Equatable {
            case topLeading
            case topTrailing
            case bottomLeading
            case bottomTrailing
        }

        var presentation: Presentation = .collapsed
        var corner: Corner = .bottomTrailing

        /// Expand the collapsed button into the floating panel.
        func open() {
            presentation = .floating
        }

        /// Return to the collapsed button from any expanded state.
        func close() {
            presentation = .collapsed
        }

        /// Toggle between the floating panel and full screen. A no-op from
        /// `collapsed` (there's no panel to resize yet).
        func toggleFullScreen() {
            switch presentation {
                case .collapsed: break
                case .floating: presentation = .fullScreen
                case .fullScreen: presentation = .floating
            }
        }

        /// The nearest resting corner for a drop `point` within a container of
        /// `size`, chosen by which quadrant the point falls in. Pure so the
        /// snapping is unit-testable without a view.
        nonisolated static func nearestCorner(to point: CGPoint, in size: CGSize) -> Corner {
            let isLeading = point.x < size.width / 2
            let isTop = point.y < size.height / 2
            switch (isTop, isLeading) {
                case (true, true): return .topLeading
                case (true, false): return .topTrailing
                case (false, true): return .bottomLeading
                case (false, false): return .bottomTrailing
            }
        }
    }
#endif
