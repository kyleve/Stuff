#if DEBUG
    import SwiftUI
    import WhereCore

    /// State for the developer overlay: its collapsed launcher, lightweight
    /// route menu, or one selected tool in the floating/full-screen HUD.
    ///
    /// The presentation is one enum rather than route/window `Bool`s and an
    /// optional selection, so a HUD without a tool (or a tool that is both
    /// floating and full screen) cannot be represented.
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
        /// How the overlay is shown. The selected tool travels with both HUD
        /// cases, preserving its identity across a floating/full-screen toggle.
        enum Presentation: Equatable {
            case collapsed
            case menu
            case floating(DeveloperTool)
            case fullScreen(DeveloperTool)

            var tool: DeveloperTool? {
                switch self {
                    case .collapsed, .menu: nil
                    case let .floating(tool), let .fullScreen(tool): tool
                }
            }

            var isMenuPresented: Bool {
                self == .menu
            }

            var isFullScreen: Bool {
                if case .fullScreen = self { true } else { false }
            }

            /// Menu interaction is modal despite its clear backdrop; the
            /// full-screen HUD is modal because it covers the app.
            var isAccessibilityModal: Bool {
                switch self {
                    case .menu, .fullScreen: true
                    case .collapsed, .floating: false
                }
            }
        }

        /// The resting corner of the collapsed button. Snapped to on drag end, so
        /// the button always parks in a predictable spot rather than mid-screen.
        /// String-backed so each case round-trips through the store verbatim.
        enum Corner: String, Equatable {
            case topLeading
            case topTrailing
            case bottomLeading
            case bottomTrailing

            var isTop: Bool {
                switch self {
                    case .topLeading, .topTrailing: true
                    case .bottomLeading, .bottomTrailing: false
                }
            }

            var isLeading: Bool {
                switch self {
                    case .topLeading, .bottomLeading: true
                    case .topTrailing, .bottomTrailing: false
                }
            }
        }

        /// The floating window's geometry: its center in the container's
        /// (safe-area) coordinate space and its size. A single value so the two
        /// can't drift, and `Equatable` so a no-op commit is cheap to detect.
        struct FloatingLayout: Equatable {
            var center: CGPoint
            var size: CGSize
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
        init(
            store: any KeyValueStore = UserDefaults.standard,
            initialPresentation: Presentation = .collapsed,
            initialCorner: Corner? = nil,
        ) {
            self.store = store
            presentation = initialPresentation
            // Assigning in `init` doesn't fire an observer, so loading here can't
            // re-persist what we just read.
            if let initialCorner {
                corner = initialCorner
            } else if let raw = store.object(forKey: Keys.corner.rawValue) as? String,
                      let restored = Corner(rawValue: raw)
            {
                corner = restored
            }
            floating = Self.loadLayout(from: store)
        }

        /// Expand the collapsed launcher into the route menu.
        func openMenu() {
            guard presentation == .collapsed else { return }
            presentation = .menu
        }

        /// Collapse the route menu. A selected tool must close through
        /// ``closeTool()`` so unrelated states cannot dismiss one another.
        func closeMenu() {
            guard presentation == .menu else { return }
            presentation = .collapsed
        }

        /// Replace the menu with a floating HUD rooted at `tool`.
        func open(_ tool: DeveloperTool) {
            guard presentation == .menu else { return }
            presentation = .floating(tool)
        }

        /// Close a selected tool back to the collapsed launcher.
        func closeTool() {
            guard presentation.tool != nil else { return }
            presentation = .collapsed
        }

        /// Toggle the selected tool between its floating HUD and full screen. A
        /// no-op from the launcher/menu states, where there is no tool to resize.
        func toggleFullScreen() {
            switch presentation {
                case .collapsed, .menu:
                    break
                case let .floating(tool):
                    presentation = .fullScreen(tool)
                case let .fullScreen(tool):
                    presentation = .floating(tool)
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
        nonisolated static func defaultLayout(
            in container: CGSize,
            style: WhereStylesheet.DeveloperOverlayStyle.FloatingWindow = .standard,
            edgeInset: CGFloat = WhereStylesheet.DeveloperOverlayStyle.standard.edgeInset,
        ) -> FloatingLayout {
            let width = min(max(container.width - edgeInset * 2, 0), style.maxWidth)
            let height = min(container.height * style.heightFraction, style.maxHeight)
            let layout = FloatingLayout(
                center: CGPoint(x: container.width / 2, y: container.height / 2),
                size: CGSize(width: width, height: max(height, 0)),
            )
            return clamp(layout, in: container, style: style)
        }

        /// Keep a layout fully on-screen within `container`, enforcing the minimum
        /// size. Size is clamped first (never larger than the container, never
        /// smaller than `Layout.minSize`), then the center so no edge escapes.
        nonisolated static func clamp(
            _ layout: FloatingLayout,
            in container: CGSize,
            style: WhereStylesheet.DeveloperOverlayStyle.FloatingWindow = .standard,
        ) -> FloatingLayout {
            var size = layout.size
            size.width = min(
                max(size.width, style.minSize.width),
                max(container.width, style.minSize.width),
            )
            size.height = min(
                max(size.height, style.minSize.height),
                max(container.height, style.minSize.height),
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
            style: WhereStylesheet.DeveloperOverlayStyle.FloatingWindow = .standard,
        ) -> FloatingLayout {
            var moved = base
            moved.center.x += translation.width
            moved.center.y += translation.height
            return clamp(moved, in: container, style: style)
        }

        /// `base` resized by a bottom-trailing drag `translation`: the top-leading
        /// corner stays pinned (so the window grows toward the drag), the size is
        /// clamped to the min and to what fits from that anchor, then re-clamped
        /// into `container`.
        nonisolated static func resized(
            _ base: FloatingLayout,
            by translation: CGSize,
            in container: CGSize,
            style: WhereStylesheet.DeveloperOverlayStyle.FloatingWindow = .standard,
        ) -> FloatingLayout {
            let topLeading = CGPoint(
                x: base.center.x - base.size.width / 2,
                y: base.center.y - base.size.height / 2,
            )
            var size = CGSize(
                width: base.size.width + translation.width,
                height: base.size.height + translation.height,
            )
            size.width = max(size.width, style.minSize.width)
            size.height = max(size.height, style.minSize.height)
            size.width = min(size.width, max(container.width - topLeading.x, style.minSize.width))
            size.height = min(
                size.height,
                max(container.height - topLeading.y, style.minSize.height),
            )
            let center = CGPoint(
                x: topLeading.x + size.width / 2,
                y: topLeading.y + size.height / 2,
            )
            return clamp(FloatingLayout(center: center, size: size), in: container, style: style)
        }

        /// The safe-area inset the floating window's footprint claims on each edge
        /// it's docked to, so app content behind the non-modal HUD can scroll clear
        /// of it. Expects an on-screen `layout` (the caller clamps first).
        ///
        /// An edge counts as docked only when the window's near edge is within
        /// `edgeTolerance` of the container edge **and** its far edge leaves the
        /// opposite edge free — so there's actually room to push content aside.
        /// This means a window spanning an axis (near both edges, e.g. the near
        /// full-width default) claims nothing on that axis, and a window can dock
        /// at most one edge per axis. Each inset is capped at
        /// `Layout.maxContentInsetFraction` of the container so a large window
        /// can't collapse the content behind it to nothing.
        nonisolated static func contentInsets(
            for layout: FloatingLayout,
            in container: CGSize,
            edgeTolerance: CGFloat,
            style: WhereStylesheet.DeveloperOverlayStyle.FloatingWindow = .standard,
        ) -> EdgeInsets {
            guard container.width > 0, container.height > 0 else { return EdgeInsets() }
            let minX = layout.center.x - layout.size.width / 2
            let maxX = layout.center.x + layout.size.width / 2
            let minY = layout.center.y - layout.size.height / 2
            let maxY = layout.center.y + layout.size.height / 2
            let maxVertical = container.height * style.maxContentInsetFraction
            let maxHorizontal = container.width * style.maxContentInsetFraction

            let nearTop = minY <= edgeTolerance
            let nearBottom = maxY >= container.height - edgeTolerance
            let nearLeading = minX <= edgeTolerance
            let nearTrailing = maxX >= container.width - edgeTolerance

            var insets = EdgeInsets()
            if nearTop, !nearBottom {
                insets.top = min(max(0, maxY), maxVertical)
            } else if nearBottom, !nearTop {
                insets.bottom = min(max(0, container.height - minY), maxVertical)
            }
            if nearLeading, !nearTrailing {
                insets.leading = min(max(0, maxX), maxHorizontal)
            } else if nearTrailing, !nearLeading {
                insets.trailing = min(max(0, container.width - minX), maxHorizontal)
            }
            return insets
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
