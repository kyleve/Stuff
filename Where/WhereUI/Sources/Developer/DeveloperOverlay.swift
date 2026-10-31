#if DEBUG
    import PeriscopeTools
    import SnapshotKit
    import SwiftUI
    import UIKit
    import WhereCore

    /// A global, DEBUG-only developer launcher and tool surface above the app.
    ///
    /// Collapsed, it's a small draggable button (``DeveloperOverlayButton``) that
    /// snaps to the nearest corner. Tapping unfolds a labeled glass accordion
    /// directly over the app; its clear backdrop consumes an outside tap without
    /// visually dimming the app. Choosing a route replaces the menu with the
    /// selected tool in a Liquid Glass HUD — draggable, resizable, and able to
    /// grow into an inset full-screen modal. Flyover is the exception: it owns an
    /// independent navigation domain and opens in a full-screen cover.
    ///
    /// The floating HUD reports its footprint through
    /// ``DeveloperOverlayInsetKey`` so app content scrolls clear of it. The tool
    /// host keeps its identity across floating/full-screen changes, preserving
    /// the tool's navigation state; closing it returns to the collapsed launcher.
    ///
    /// Attached once at ``RootView`` and compiled out of release (`#if DEBUG`).
    struct DeveloperOverlay: View {
        /// Native bar clearance measured on each edge by the active tab.
        /// RootView passes it to this sibling overlay. Zero when logged out.
        private let tabBarInset: EdgeInsets

        @State private var model: DeveloperOverlayModel
        @State private var dragOffset: CGSize = .zero
        @State private var isDraggingButton = false
        @State private var isPresentingFlyover = false
        @State private var isPresentingDemoConfiguration = false
        /// The collapsed button's rendered size, measured rather than hardcoded so
        /// the drag/anchor math tracks whatever ``DeveloperOverlayButton`` draws
        /// (it scales with Dynamic Type).
        @State private var buttonSize: CGSize = .zero
        /// In-flight window move / resize translation, held in the view (not the
        /// model) so the persisted layout is written *once* on gesture end rather
        /// than every frame.
        @State private var windowDrag: CGSize = .zero
        @State private var windowResize: CGSize = .zero

        @Environment(\.stylesheet) private var stylesheet
        // Gesture points and reserved-region frames use physical container coordinates.
        @Environment(\.layoutDirection) private var layoutDirection
        @Environment(WhereDeveloperLaunchController.self) private var launchController:
            WhereDeveloperLaunchController?

        init(tabBarInset: EdgeInsets = EdgeInsets()) {
            self.tabBarInset = tabBarInset
            _model = State(initialValue: DeveloperOverlayModel())
        }

        init(tabBarInset: EdgeInsets = EdgeInsets(), model: DeveloperOverlayModel) {
            self.tabBarInset = tabBarInset
            _model = State(initialValue: model)
        }

        var body: some View {
            AdaptiveHistoryGeometryReader { geometry in
                let leadingIsLeft = layoutDirection == .leftToRight
                let preferred = CGPoint(
                    x: model.corner.isLeading == leadingIsLeft ? geometry.contentBounds
                        .minX : geometry.contentBounds.maxX,
                    y: model.corner.isTop ? geometry.contentBounds.minY : geometry.contentBounds
                        .maxY,
                )
                let area = geometry.unobstructedBounds(near: preferred)
                let container = area.size
                let style = stylesheet.developerOverlay
                let anchor = anchorPoint(for: model.corner, in: container)
                let menuFrame = menuFrame(anchor: anchor, in: container)

                ZStack {
                    if model.presentation.isFullScreen {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .transition(.opacity)
                    }

                    if model.presentation.isMenuPresented {
                        Button(action: closeMenu) {
                            Color.clear
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHidden(true)
                    }

                    // Kept mounted in every state so menu rows can animate out in
                    // reverse even while the selected tool HUD animates in.
                    DeveloperOverlayMenu(
                        isPresented: model.presentation.isMenuPresented,
                        corner: model.corner,
                        maxHeight: menuFrame.height,
                        onOpenDestination: openDestination,
                        onConfigureDemo: configureDemo,
                    )
                    .frame(width: menuFrame.width, height: menuFrame.height)
                    .position(x: menuFrame.midX, y: menuFrame.midY)

                    if let tool = model.presentation.tool {
                        panel(
                            tool: tool,
                            isFullScreen: model.presentation.isFullScreen,
                            in: container,
                        )
                    }

                    if model.presentation.tool == nil {
                        DeveloperOverlayButton(
                            isMenuPresented: model.presentation.isMenuPresented,
                            action: toggleMenu,
                        )
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { buttonSize = $0 }
                        .position(
                            x: anchor.x + dragOffset.width,
                            y: anchor.y + dragOffset.height,
                        )
                        .simultaneousGesture(
                            dragGesture(in: container),
                            isEnabled: model.presentation == .collapsed,
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: area.width, height: area.height)
                .position(x: area.midX, y: area.midY)
                .animation(style.presentationAnimation, value: model.presentation)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(
                    model.presentation.isAccessibilityModal ? .isModal : [],
                )
                // Report the footprint the non-modal HUD occupies so `RootView`
                // can inset the app content behind it.
                .preference(
                    key: DeveloperOverlayInsetKey.self,
                    value: appContentInsets(in: geometry.contentBounds.size, area: area),
                )
            }
            .padding(tabBarInset)
            .fullScreenCover(isPresented: $isPresentingFlyover) {
                WhereFlyoverPresentationView()
            }
            .sheet(isPresented: $isPresentingDemoConfiguration) {
                if let launchController {
                    DeveloperDemoLaunchSheet(controller: launchController)
                }
            }
            // Menu and full-screen states are modal to VoiceOver. Crossing either
            // boundary moves focus into/out of the active developer surface.
            .onChange(of: model.presentation) { old, new in
                let modalChanged = old.isAccessibilityModal != new.isAccessibilityModal
                UIAccessibility.post(
                    notification: modalChanged ? .screenChanged : .layoutChanged,
                    argument: nil,
                )
            }
        }

        private func toggleMenu() {
            guard isDraggingButton == false else { return }
            let motion = stylesheet.developerOverlay.menu.motion.animation
            withAnimation(motion) {
                if model.presentation.isMenuPresented {
                    model.closeMenu()
                } else {
                    model.openMenu()
                }
            }
        }

        private func closeMenu() {
            withAnimation(stylesheet.developerOverlay.menu.motion.animation) {
                model.closeMenu()
            }
        }

        private func configureDemo() {
            withAnimation(stylesheet.developerOverlay.menu.motion.animation) {
                model.closeMenu()
            }
            isPresentingDemoConfiguration = true
        }

        private func openDestination(_ destination: DeveloperDestination) {
            switch destination {
                case let .tool(tool):
                    withAnimation(stylesheet.developerOverlay.presentationAnimation) {
                        model.open(tool)
                    }
                case .flyover:
                    withAnimation(stylesheet.developerOverlay.menu.motion.animation) {
                        model.closeMenu()
                    }
                    isPresentingFlyover = true
            }
        }

        private func dragGesture(in container: CGSize) -> some Gesture {
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    isDraggingButton = true
                    dragOffset = value.translation
                }
                .onEnded { value in
                    let anchor = anchorPoint(for: model.corner, in: container)
                    let dropPoint = CGPoint(
                        x: anchor.x + value.translation.width,
                        y: anchor.y + value.translation.height,
                    )
                    let newCorner = DeveloperOverlayModel.nearestCorner(
                        to: CGPoint(
                            x: layoutDirection == .leftToRight ? dropPoint.x : container
                                .width - dropPoint.x,
                            y: dropPoint.y,
                        ),
                        in: container,
                    )
                    withAnimation(stylesheet.developerOverlay.presentationAnimation) {
                        model.setCorner(newCorner)
                        dragOffset = .zero
                    }
                    // Keep the suppression flag set through the release event so
                    // the semantic Button does not also open the menu after a drag.
                    Task { @MainActor in
                        await Task.yield()
                        isDraggingButton = false
                    }
                }
        }

        /// The container already excludes the window and tab bar's independent edges.
        private func anchorPoint(
            for corner: DeveloperOverlayModel.Corner,
            in size: CGSize,
        ) -> CGPoint {
            let halfWidth = buttonSize.width / 2
            let halfHeight = buttonSize.height / 2
            let edgeInset = stylesheet.developerOverlay.edgeInset
            let leftX = edgeInset + halfWidth
            let rightX = size.width - edgeInset - halfWidth
            let leadingX = layoutDirection == .leftToRight ? leftX : rightX
            let trailingX = layoutDirection == .leftToRight ? rightX : leftX
            let topY = edgeInset + halfHeight
            let bottomY = size.height - edgeInset - halfHeight
            switch corner {
                case .topLeading: return CGPoint(x: leadingX, y: topY)
                case .topTrailing: return CGPoint(x: trailingX, y: topY)
                case .bottomLeading: return CGPoint(x: leadingX, y: bottomY)
                case .bottomTrailing: return CGPoint(x: trailingX, y: bottomY)
            }
        }

        private func menuFrame(anchor: CGPoint, in container: CGSize) -> CGRect {
            let style = stylesheet.developerOverlay
            let menuWidth = min(
                style.menu.maxWidth,
                max(container.width - style.edgeInset * 2, 0),
            )
            let buttonHalfHeight = buttonSize.height / 2
            let startY: CGFloat
            let endY: CGFloat
            if model.corner.isTop {
                startY = anchor.y + buttonHalfHeight + style.menu.launcherSpacing
                endY = container.height - style.edgeInset
            } else {
                startY = style.edgeInset
                endY = anchor.y - buttonHalfHeight - style.menu.launcherSpacing
            }
            let height = max(endY - startY, 0)
            let minX = model.corner.isLeading == (layoutDirection == .leftToRight)
                ? style.edgeInset
                : container.width - style.edgeInset - menuWidth
            return CGRect(x: minX, y: startY, width: menuWidth, height: height)
        }

        private func panel(
            tool: DeveloperTool,
            isFullScreen: Bool,
            in container: CGSize,
        ) -> some View {
            let style = stylesheet.developerOverlay
            let layout = displayedLayout(in: container)
            let size = isFullScreen ? fullScreenSize(in: container) : layout.size
            let center = isFullScreen
                ? CGPoint(x: container.width / 2, y: container.height / 2)
                : layout.center
            let shape = RoundedRectangle(cornerRadius: style.panel.cornerRadius)
            return DeveloperSurface(
                tool: tool,
                isFullScreen: isFullScreen,
                onToggleFullScreen: {
                    withAnimation(style.presentationAnimation) { model.toggleFullScreen() }
                },
                onClose: {
                    withAnimation(style.presentationAnimation) { model.closeTool() }
                },
                onMove: { translation, ended in
                    moveWindow(by: translation, ended: ended, in: container)
                },
                onResize: { translation, ended in
                    resizeWindow(by: translation, ended: ended, in: container)
                },
            )
            .frame(width: size.width, height: size.height)
            .glassEffect(.regular, in: shape)
            .clipShape(shape)
            .shadow(
                color: .black.opacity(isFullScreen ? 0 : style.panel.shadowOpacity),
                radius: style.panel.shadowRadius,
                y: style.panel.shadowOffsetY,
            )
            .position(x: center.x, y: center.y)
            .transition(.scale(scale: 0.12, anchor: .bottomTrailing).combined(with: .opacity))
        }

        /// The floating window's resting geometry: its persisted layout (or the
        /// default), always clamped to the *current* container. Clamping here is
        /// what keeps a window persisted in one orientation / size class / device
        /// from opening off-screen or oversized in another — persisted values were
        /// only clamped for the container that was current when they were written.
        /// Display and the gesture-end commit share this so they can't disagree.
        private func currentBase(in container: CGSize) -> DeveloperOverlayModel.FloatingLayout {
            let style = stylesheet.developerOverlay
            return DeveloperOverlayModel.clamp(
                model.floating ?? DeveloperOverlayModel.defaultLayout(
                    in: container,
                    style: style.floatingWindow,
                    edgeInset: style.edgeInset,
                ),
                in: container,
                style: style.floatingWindow,
            )
        }

        /// The floating window's on-screen geometry: its resting layout with the
        /// in-flight drag / resize translation applied. Never written back to the
        /// model during layout — the model is only updated at gesture end (see
        /// `moveWindow` / `resizeWindow`).
        private func displayedLayout(in container: CGSize) -> DeveloperOverlayModel.FloatingLayout {
            let style = stylesheet.developerOverlay.floatingWindow
            let base = currentBase(in: container)
            let resized = windowResize == .zero
                ? base
                : DeveloperOverlayModel.resized(
                    base,
                    by: windowResize,
                    in: container,
                    style: style,
                )
            return windowDrag == .zero
                ? resized
                : DeveloperOverlayModel.moved(
                    resized,
                    by: windowDrag,
                    in: container,
                    style: style,
                )
        }

        private func fullScreenSize(in container: CGSize) -> CGSize {
            let inset = stylesheet.developerOverlay.panel.fullScreenInset
            return CGSize(
                width: max(container.width - inset * 2, 0),
                height: max(container.height - inset * 2, 0),
            )
        }

        private func moveWindow(by translation: CGSize, ended: Bool, in container: CGSize) {
            if ended {
                let base = currentBase(in: container)
                model.setFloating(DeveloperOverlayModel.moved(
                    base,
                    by: translation,
                    in: container,
                    style: stylesheet.developerOverlay.floatingWindow,
                ))
                windowDrag = .zero
            } else {
                windowDrag = translation
            }
        }

        private func resizeWindow(by translation: CGSize, ended: Bool, in container: CGSize) {
            if ended {
                let base = currentBase(in: container)
                model
                    .setFloating(DeveloperOverlayModel.resized(
                        base,
                        by: translation,
                        in: container,
                        style: stylesheet.developerOverlay.floatingWindow,
                    ))
                windowResize = .zero
            } else {
                windowResize = translation
            }
        }

        /// The safe-area inset the floating HUD occupies, so `RootView` can push
        /// app content clear of it. Zero unless floating; the docking math + cap
        /// live in ``DeveloperOverlayModel/contentInsets(for:in:edgeTolerance:)``,
        /// fed the on-screen (clamped) `displayedLayout`.
        private func appContentInsets(in container: CGSize, area: CGRect) -> EdgeInsets {
            guard case .floating = model.presentation else { return EdgeInsets() }
            let style = stylesheet.developerOverlay
            var layout = displayedLayout(in: area.size)
            layout.center.x += area.minX
            layout.center.y += area.minY
            return DeveloperOverlayModel.contentInsets(
                for: layout,
                in: container,
                edgeTolerance: style.edgeInset,
                style: style.floatingWindow,
            )
        }
    }

    extension DeveloperOverlay: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Collapsed", configurations: .phoneLightDark) {
                DeveloperOverlayPreview(presentation: .collapsed)
            }
            whereSnapshot(
                name: "MenuBottomTrailing",
                configurations: .fullContentPhoneLightDark,
            ) {
                DeveloperOverlayPreview(presentation: .menu)
            }
            whereSnapshot(
                name: "MenuTopLeading",
                configurations: SnapshotConfiguration.combinations(devices: [.iPhoneFullContent]),
            ) {
                DeveloperOverlayPreview(presentation: .menu, corner: .topLeading)
            }
            whereSnapshot(
                name: "SelectedTool",
                configurations: SnapshotConfiguration.combinations(devices: [.iPhone]),
            ) {
                DeveloperOverlayPreview(presentation: .floating(.openSpans))
            }
        }
    }

    #Preview {
        DeveloperOverlay.snapshotPreviews
    }
#endif

#if DEBUG
    extension DeveloperOverlay: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            DeveloperOverlay.self,
            title: "Developer Overlay",
            navigationContainer: .none,
            routes: [
                .push(to: WhereFlyoverLogView.flyoverID),
                .push(to: OpenSpansView.flyoverID),
                .push(to: RegionMapView.flyoverID),
            ],
        )
    }
#endif
