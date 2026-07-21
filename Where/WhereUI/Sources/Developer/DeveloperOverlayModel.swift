#if DEBUG
    import SwiftUI
    import WhereCore

    /// State for the floating developer overlay: how it's currently presented,
    /// which corner the collapsed button rests in, and — while floating — the
    /// window's dragged position and resized dimensions.
    ///
    /// The presentation is a single enum rather than a set of `Bool`s so the
    /// illegal combinations (e.g. "floating *and* full screen") can't be spelled.
    ///
    /// The floating window's geometry (`floating`) and resting `corner` persist
    /// across launches through an injected ``KeyValueStore`` (production
    /// `UserDefaults`, an in-memory double in tests) so the window reopens where
    /// it was left. Persistence is deliberately kept *local to this DEBUG-only
    /// surface* rather than routed through the shipping `WherePreferences` — dev
    /// window geometry is developer chrome, not product/user intent, and must not
    /// pollute a shipping type or its `reset()`. Writes happen only at gesture
    /// *commit* points (drag/resize end), never per frame — the in-flight
    /// translation lives in the view, so `floating` changes (and its one store
    /// write) fire once per gesture.
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
        /// String-backed so each case round-trips through the store verbatim.
        enum Corner: String, Equatable {
            case topLeading
            case topTrailing
            case bottomLeading
            case bottomTrailing
        }

        /// The floating window's geometry: its center in the container's
        /// (safe-area) coordinate space and its size. A single value so the two
        /// can't drift, and `Equatable` so a no-op commit is cheap to detect.
        struct FloatingLayout: Equatable {
            var center: CGPoint
            var size: CGSize
        }

        /// Sizing/spacing constants for the floating window, kept here (rather than
        /// in the view) so the pure layout math below is self-contained and
        /// unit-testable.
        enum Layout {
            static let edgeInset: CGFloat = 16
            static let maxWidth: CGFloat = 420
            static let maxHeight: CGFloat = 620
            static let heightFraction: CGFloat = 0.62
            static let minSize = CGSize(width: 260, height: 320)
        }

        private let store: any KeyValueStore

        var presentation: Presentation = .collapsed
        var corner: Corner = .bottomTrailing
        /// The floating window's geometry, or `nil` until the user first drags or
        /// resizes it — `nil` means "never positioned", so the window opens
        /// centered at the default size (see ``defaultLayout(in:)``).
        var floating: FloatingLayout?

        /// - Parameter store: where the window geometry + corner persist. Defaults
        ///   to `UserDefaults.standard`; tests inject an `InMemoryKeyValueStore`.
        init(store: any KeyValueStore = UserDefaults.standard) {
            self.store = store
            // Assigning in `init` doesn't fire an observer, so loading here can't
            // re-persist what we just read.
            if let raw = store.object(forKey: Keys.corner.rawValue) as? String,
               let restored = Corner(rawValue: raw)
            {
                corner = restored
            }
            floating = Self.loadLayout(from: store)
        }

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

        // MARK: Commit points (persist)

        /// Commit the collapsed button's resting corner (drag end).
        func setCorner(_ corner: Corner) {
            guard self.corner != corner else { return }
            self.corner = corner
            store.set(corner.rawValue, forKey: Keys.corner.rawValue)
        }

        /// Commit the floating window's geometry (drag/resize end). The caller
        /// passes an already-clamped layout (via ``moved(_:by:in:)`` /
        /// ``resized(_:by:in:)``); this only stores it once.
        func setFloating(_ layout: FloatingLayout) {
            guard floating != layout else { return }
            floating = layout
            store.set(Double(layout.center.x), forKey: Keys.floatingCenterX.rawValue)
            store.set(Double(layout.center.y), forKey: Keys.floatingCenterY.rawValue)
            store.set(Double(layout.size.width), forKey: Keys.floatingWidth.rawValue)
            store.set(Double(layout.size.height), forKey: Keys.floatingHeight.rawValue)
        }

        // MARK: Pure geometry (unit-testable without a view)

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

        /// The centered, default-sized floating window for a given container —
        /// used the first time the window opens (before the user has moved it).
        nonisolated static func defaultLayout(in container: CGSize) -> FloatingLayout {
            let width = min(max(container.width - Layout.edgeInset * 2, 0), Layout.maxWidth)
            let height = min(container.height * Layout.heightFraction, Layout.maxHeight)
            let layout = FloatingLayout(
                center: CGPoint(x: container.width / 2, y: container.height / 2),
                size: CGSize(width: width, height: max(height, 0)),
            )
            return clamp(layout, in: container)
        }

        /// Keep a layout fully on-screen within `container`, enforcing the minimum
        /// size. Size is clamped first (never larger than the container, never
        /// smaller than `Layout.minSize`), then the center so no edge escapes.
        nonisolated static func clamp(
            _ layout: FloatingLayout,
            in container: CGSize,
        ) -> FloatingLayout {
            var size = layout.size
            size.width = min(
                max(size.width, Layout.minSize.width),
                max(container.width, Layout.minSize.width),
            )
            size.height = min(
                max(size.height, Layout.minSize.height),
                max(container.height, Layout.minSize.height),
            )

            let halfWidth = size.width / 2
            let halfHeight = size.height / 2
            var center = layout.center
            let minX = halfWidth, maxX = container.width - halfWidth
            let minY = halfHeight, maxY = container.height - halfHeight
            center.x = maxX >= minX ? min(max(center.x, minX), maxX) : container.width / 2
            center.y = maxY >= minY ? min(max(center.y, minY), maxY) : container.height / 2
            return FloatingLayout(center: center, size: size)
        }

        /// `base` shifted by a drag `translation`, clamped back into `container`.
        nonisolated static func moved(
            _ base: FloatingLayout,
            by translation: CGSize,
            in container: CGSize,
        ) -> FloatingLayout {
            var moved = base
            moved.center.x += translation.width
            moved.center.y += translation.height
            return clamp(moved, in: container)
        }

        /// `base` resized by a bottom-trailing drag `translation`: the top-leading
        /// corner stays pinned (so the window grows toward the drag), the size is
        /// clamped to the min and to what fits from that anchor, then re-clamped
        /// into `container`.
        nonisolated static func resized(
            _ base: FloatingLayout,
            by translation: CGSize,
            in container: CGSize,
        ) -> FloatingLayout {
            let topLeading = CGPoint(
                x: base.center.x - base.size.width / 2,
                y: base.center.y - base.size.height / 2,
            )
            var size = CGSize(
                width: base.size.width + translation.width,
                height: base.size.height + translation.height,
            )
            size.width = max(size.width, Layout.minSize.width)
            size.height = max(size.height, Layout.minSize.height)
            size.width = min(size.width, max(container.width - topLeading.x, Layout.minSize.width))
            size.height = min(
                size.height,
                max(container.height - topLeading.y, Layout.minSize.height),
            )
            let center = CGPoint(
                x: topLeading.x + size.width / 2,
                y: topLeading.y + size.height / 2,
            )
            return clamp(FloatingLayout(center: center, size: size), in: container)
        }

        // MARK: Persistence

        private static func loadLayout(from store: any KeyValueStore) -> FloatingLayout? {
            guard let x = store.object(forKey: Keys.floatingCenterX.rawValue) as? Double,
                  let y = store.object(forKey: Keys.floatingCenterY.rawValue) as? Double,
                  let width = store.object(forKey: Keys.floatingWidth.rawValue) as? Double,
                  let height = store.object(forKey: Keys.floatingHeight.rawValue) as? Double
            else { return nil }
            return FloatingLayout(
                center: CGPoint(x: x, y: y),
                size: CGSize(width: width, height: height),
            )
        }

        /// DEBUG-only defaults keys for the developer window's persisted geometry.
        private enum Keys: String {
            case corner = "where.developer.corner"
            case floatingCenterX = "where.developer.floating.centerX"
            case floatingCenterY = "where.developer.floating.centerY"
            case floatingWidth = "where.developer.floating.width"
            case floatingHeight = "where.developer.floating.height"
        }
    }
#endif
