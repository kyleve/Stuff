#if DEBUG
    import SwiftUI
    import UIKit

    /// A global, DEBUG-only developer surface that floats above the entire app.
    ///
    /// Collapsed, it's a small draggable button (``DeveloperOverlayButton``) that
    /// snaps to the nearest corner. Tapping expands it into a Liquid Glass HUD
    /// window hosting ``DeveloperToolsView`` — draggable by its top bar and
    /// resizable from a bottom-trailing grip, with its position and size persisted
    /// across launches (see ``DeveloperOverlayModel``). From there it grows to an
    /// inset full-screen modal and shrinks back. In the collapsed and floating
    /// states the rest of the app stays interactive behind it — only the
    /// button/window capture touches — so the tools are reachable from anywhere,
    /// including before login.
    ///
    /// Because the floating HUD is non-modal, it also reports the footprint it
    /// occupies (``DeveloperOverlayInsetKey``) so ``RootView`` can extend the app
    /// content's safe area and screens behind it scroll clear of the window.
    ///
    /// The tools surface keeps its navigation state across the floating ↔ full
    /// screen toggle because it stays the *same* view (only its frame changes);
    /// only the collapsed ↔ expanded change swaps view identity.
    ///
    /// Attached once at ``RootView`` and compiled out of release (`#if DEBUG`).
    struct DeveloperOverlay: View {
        /// The logged-in tab bar's height, measured by `MainTabs` and threaded in
        /// via `RootView`, so the resting button clears the floating tab bar
        /// without hardcoding its height. Zero when logged out.
        var tabBarInset: CGFloat = 0

        @State private var model = DeveloperOverlayModel()
        @State private var dragOffset: CGSize = .zero
        /// The collapsed button's rendered size, measured rather than hardcoded so
        /// the drag/anchor math tracks whatever ``DeveloperOverlayButton`` draws
        /// (it scales with Dynamic Type).
        @State private var buttonSize: CGSize = .zero
        /// In-flight window move / resize translation, held in the view (not the
        /// model) so the persisted layout is written *once* on gesture end rather
        /// than every frame.
        @State private var windowDrag: CGSize = .zero
        @State private var windowResize: CGSize = .zero

        private let edgeInset: CGFloat = 16
        private let panelCornerRadius: CGFloat = 22
        /// Margin around the inset full-screen modal, so it reads as a devtools
        /// modal floating over the app rather than replacing it edge-to-edge.
        private let fullScreenInset: CGFloat = 12

        var body: some View {
            GeometryReader { proxy in
                ZStack {
                    // A dimmed scrim only in full screen; it still captures touches
                    // (blocking the app behind the modal) but lets the inset edges
                    // hint at the app underneath. The floating (HUD) state has no
                    // scrim — the app behind stays visible and usable.
                    if model.presentation == .fullScreen {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .transition(.opacity)
                    }

                    switch model.presentation {
                        case .collapsed:
                            collapsedButton(in: proxy)
                        case .floating, .fullScreen:
                            panel(in: proxy)
                    }
                }
                .animation(.snappy(duration: 0.3), value: model.presentation)
                // Report the footprint the non-modal HUD occupies so `RootView`
                // can inset the app content behind it.
                .preference(
                    key: DeveloperOverlayInsetKey.self,
                    value: appContentInsets(in: proxy.size),
                )
            }
            // Nudge VoiceOver to re-scan when the surface changes: crossing the
            // full-screen boundary flips the modal (see `panel`), so post
            // `.screenChanged` to move focus into/out of the modal; the lighter
            // open/close of the non-modal floating panel only warrants
            // `.layoutChanged`.
            .onChange(of: model.presentation) { old, new in
                let modalChanged = (old == .fullScreen) != (new == .fullScreen)
                UIAccessibility.post(
                    notification: modalChanged ? .screenChanged : .layoutChanged,
                    argument: nil,
                )
            }
        }

        // MARK: Collapsed button

        private func collapsedButton(in proxy: GeometryProxy) -> some View {
            let anchor = anchorPoint(for: model.corner, in: proxy.size)
            return DeveloperOverlayButton()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { buttonSize = $0 }
                .position(x: anchor.x + dragOffset.width, y: anchor.y + dragOffset.height)
                .gesture(dragGesture(in: proxy))
                .onTapGesture { model.open() }
                .transition(.scale.combined(with: .opacity))
        }

        private func dragGesture(in proxy: GeometryProxy) -> some Gesture {
            // A small minimum distance lets a stationary tap fall through to
            // `onTapGesture` (open) while any real drag moves the button.
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    let anchor = anchorPoint(for: model.corner, in: proxy.size)
                    let dropPoint = CGPoint(
                        x: anchor.x + value.translation.width,
                        y: anchor.y + value.translation.height,
                    )
                    let newCorner = DeveloperOverlayModel.nearestCorner(
                        to: dropPoint,
                        in: proxy.size,
                    )
                    withAnimation(.snappy(duration: 0.3)) {
                        model.setCorner(newCorner)
                        dragOffset = .zero
                    }
                }
        }

        /// Resting center for the button in a given corner. `size` is already the
        /// safe-area region (the `GeometryReader` respects the safe area), so the
        /// only extra offset is the measured tab-bar height on the bottom corners
        /// so the button clears the floating tab bar when logged in.
        private func anchorPoint(
            for corner: DeveloperOverlayModel.Corner,
            in size: CGSize,
        ) -> CGPoint {
            let halfWidth = buttonSize.width / 2
            let halfHeight = buttonSize.height / 2
            let leadingX = edgeInset + halfWidth
            let trailingX = size.width - edgeInset - halfWidth
            let topY = edgeInset + halfHeight
            let bottomY = size.height - tabBarInset - edgeInset - halfHeight
            switch corner {
                case .topLeading: return CGPoint(x: leadingX, y: topY)
                case .topTrailing: return CGPoint(x: trailingX, y: topY)
                case .bottomLeading: return CGPoint(x: leadingX, y: bottomY)
                case .bottomTrailing: return CGPoint(x: trailingX, y: bottomY)
            }
        }

        // MARK: Expanded panel

        private func panel(in proxy: GeometryProxy) -> some View {
            let isFullScreen = model.presentation == .fullScreen
            let layout = displayedLayout(in: proxy.size)
            let size = isFullScreen ? fullScreenSize(in: proxy.size) : layout.size
            let center = isFullScreen
                ? CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                : layout.center
            let shape = RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
            return DeveloperSurface(
                isFullScreen: isFullScreen,
                bottomContentInset: isFullScreen ? 0 : Self.resizeGripClearance,
                onToggleFullScreen: {
                    withAnimation(.snappy(duration: 0.3)) { model.toggleFullScreen() }
                },
                onClose: { model.close() },
                onMove: { translation, ended in
                    moveWindow(by: translation, ended: ended, in: proxy.size)
                },
                onResize: { translation, ended in
                    resizeWindow(by: translation, ended: ended, in: proxy.size)
                },
            )
            .frame(width: size.width, height: size.height)
            // One glass surface for the whole HUD (rather than glass-on-glass): the
            // list's own scroll background is cleared in `DeveloperSurface` so this
            // shows through.
            .glassEffect(.regular, in: shape)
            .clipShape(shape)
            .shadow(color: .black.opacity(isFullScreen ? 0 : 0.3), radius: 20, y: 6)
            // Full screen covers the app, so it becomes an accessibility modal:
            // VoiceOver ignores everything behind it and stays trapped in the
            // tools. The floating HUD stays non-modal — the app behind is still
            // reachable — matching its visible, tap-through behavior.
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(isFullScreen ? .isModal : [])
            .position(x: center.x, y: center.y)
            .transition(.scale(scale: 0.12, anchor: .bottomTrailing).combined(with: .opacity))
        }

        /// The floating window's on-screen geometry: its persisted (or default)
        /// layout with the in-flight drag / resize translation applied. Never
        /// written back to the model during layout — the model is only updated at
        /// gesture end (see `moveWindow` / `resizeWindow`).
        private func displayedLayout(in container: CGSize) -> DeveloperOverlayModel.FloatingLayout {
            let base = model.floating ?? DeveloperOverlayModel.defaultLayout(in: container)
            let resized = windowResize == .zero
                ? base
                : DeveloperOverlayModel.resized(base, by: windowResize, in: container)
            return windowDrag == .zero
                ? resized
                : DeveloperOverlayModel.moved(resized, by: windowDrag, in: container)
        }

        private func fullScreenSize(in container: CGSize) -> CGSize {
            CGSize(
                width: max(container.width - fullScreenInset * 2, 0),
                height: max(container.height - fullScreenInset * 2, 0),
            )
        }

        private func moveWindow(by translation: CGSize, ended: Bool, in container: CGSize) {
            if ended {
                let base = model.floating ?? DeveloperOverlayModel.defaultLayout(in: container)
                model.setFloating(DeveloperOverlayModel.moved(base, by: translation, in: container))
                windowDrag = .zero
            } else {
                windowDrag = translation
            }
        }

        private func resizeWindow(by translation: CGSize, ended: Bool, in container: CGSize) {
            if ended {
                let base = model.floating ?? DeveloperOverlayModel.defaultLayout(in: container)
                model
                    .setFloating(DeveloperOverlayModel.resized(
                        base,
                        by: translation,
                        in: container,
                    ))
                windowResize = .zero
            } else {
                windowResize = translation
            }
        }

        /// The safe-area inset the floating HUD occupies on each edge it's docked
        /// to, so `RootView` can push app content clear of it. Zero unless
        /// floating; each axis picks the single edge the window is nearer to (so a
        /// tall window doesn't inset top *and* bottom), and reports how far the
        /// window reaches in from that edge.
        private func appContentInsets(in container: CGSize) -> EdgeInsets {
            guard model.presentation == .floating else { return EdgeInsets() }
            let layout = displayedLayout(in: container)
            let minX = layout.center.x - layout.size.width / 2
            let maxX = layout.center.x + layout.size.width / 2
            let minY = layout.center.y - layout.size.height / 2
            let maxY = layout.center.y + layout.size.height / 2
            let tolerance = edgeInset

            var insets = EdgeInsets()
            let inTopHalf = layout.center.y <= container.height / 2
            if inTopHalf {
                if minY <= tolerance { insets.top = max(0, maxY) }
            } else if maxY >= container.height - tolerance {
                insets.bottom = max(0, container.height - minY)
            }
            let inLeadingHalf = layout.center.x <= container.width / 2
            if inLeadingHalf {
                if minX <= tolerance { insets.leading = max(0, maxX) }
            } else if maxX >= container.width - tolerance {
                insets.trailing = max(0, container.width - minX)
            }
            return insets
        }

        /// Bottom content inset the tools list reserves so its last rows scroll
        /// clear of the bottom-trailing resize grip.
        private static let resizeGripClearance: CGFloat = 40
    }

    /// The chrome + content of the expanded panel: a slim HUD control strip (close
    /// / drag handle / resize) above the tools, plus a bottom-trailing resize grip.
    /// The strip lives here — outside ``DeveloperToolsView``'s own
    /// `NavigationStack` — so it stays visible no matter how deep the user
    /// navigates into a tool. Drag / resize gestures live on the handle and grip
    /// (never the whole bar) so the close / full-screen buttons stay tappable, and
    /// report their translation back to ``DeveloperOverlay`` via `onMove` /
    /// `onResize` (which own the in-flight state and the persisted commit).
    private struct DeveloperSurface: View {
        let isFullScreen: Bool
        let bottomContentInset: CGFloat
        let onToggleFullScreen: () -> Void
        let onClose: () -> Void
        /// Reports the window drag handle's translation; `ended` marks the commit.
        let onMove: (CGSize, _ ended: Bool) -> Void
        /// Reports the resize grip's translation; `ended` marks the commit.
        let onResize: (CGSize, _ ended: Bool) -> Void

        var body: some View {
            VStack(spacing: 0) {
                controlBar
                Divider().opacity(0.5)
                DeveloperToolsView(bottomContentInset: bottomContentInset)
            }
            .overlay(alignment: .bottomTrailing) {
                if !isFullScreen { resizeGrip }
            }
        }

        private var controlBar: some View {
            HStack(spacing: 0) {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel(Strings.developerClose)

                Spacer(minLength: 0)

                dragHandle

                Spacer(minLength: 0)

                Button(action: onToggleFullScreen) {
                    Image(systemName: isFullScreen
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel(isFullScreen ? Strings.developerCollapse : Strings
                    .developerExpand)
            }
            .font(.title3)
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }

        /// The grabber in the center of the control bar. It's the only drag target
        /// (the flanking buttons stay tappable); a wide content shape makes it easy
        /// to grab. Hidden in full screen, where the window fills its inset frame.
        @ViewBuilder private var dragHandle: some View {
            if isFullScreen {
                Color.clear.frame(width: 1, height: 1)
            } else {
                Capsule()
                    .fill(.secondary)
                    .frame(width: 40, height: 5)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { onMove($0.translation, false) }
                            .onEnded { onMove($0.translation, true) },
                    )
                    .accessibilityLabel(Strings.developerDragHandle)
            }
        }

        private var resizeGrip: some View {
            Image(systemName: "arrow.down.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { onResize($0.translation, false) }
                        .onEnded { onResize($0.translation, true) },
                )
                .accessibilityLabel(Strings.developerResizeHandle)
        }
    }

    #Preview("Collapsed") {
        ZStack {
            LinearGradient(
                colors: [.mint, .indigo],
                startPoint: .top,
                endPoint: .bottom,
            )
            .ignoresSafeArea()

            DeveloperOverlay()
                .environment(PreviewSupport.loadedSession())
        }
    }
#endif
