#if DEBUG
    import SnapshotKit
    import SwiftUI
    import UIKit

    /// A global, DEBUG-only developer launcher and tool surface above the app.
    ///
    /// Collapsed, it's a small draggable button (``DeveloperOverlayButton``) that
    /// snaps to the nearest corner. Tapping unfolds a labeled glass accordion
    /// directly over the app; its clear backdrop consumes an outside tap without
    /// visually dimming the app. Choosing a route replaces the menu with the
    /// selected tool in a Liquid Glass HUD — draggable, resizable, and able to
    /// grow into an inset full-screen modal.
    ///
    /// The floating HUD reports its footprint through
    /// ``DeveloperOverlayInsetKey`` so app content scrolls clear of it. The tool
    /// host keeps its identity across floating/full-screen changes, preserving
    /// the tool's navigation state; closing it returns to the collapsed launcher.
    ///
    /// Attached once at ``RootView`` and compiled out of release (`#if DEBUG`).
    struct DeveloperOverlay: View {
        /// The logged-in tab bar's height, measured by `MainTabs` and threaded in
        /// via `RootView`, so the resting button clears the floating tab bar
        /// without hardcoding its height. Zero when logged out.
        private let tabBarInset: CGFloat

        @State private var model: DeveloperOverlayModel
        @State private var dragOffset: CGSize = .zero
        @State private var isDraggingButton = false
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

        init(tabBarInset: CGFloat = 0) {
            self.tabBarInset = tabBarInset
            _model = State(initialValue: DeveloperOverlayModel())
        }

        init(tabBarInset: CGFloat = 0, model: DeveloperOverlayModel) {
            self.tabBarInset = tabBarInset
            _model = State(initialValue: model)
        }

        var body: some View {
            GeometryReader { proxy in
                let style = stylesheet.developerOverlay
                let anchor = anchorPoint(for: model.corner, in: proxy.size)
                let menuFrame = menuFrame(anchor: anchor, in: proxy.size)

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
                        onOpenTool: openTool,
                    )
                    .frame(width: menuFrame.width, height: menuFrame.height)
                    .position(x: menuFrame.midX, y: menuFrame.midY)

                    if let tool = model.presentation.tool {
                        panel(
                            tool: tool,
                            isFullScreen: model.presentation.isFullScreen,
                            in: proxy,
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
                            dragGesture(in: proxy),
                            isEnabled: model.presentation == .collapsed,
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(style.presentationAnimation, value: model.presentation)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(
                    model.presentation.isAccessibilityModal ? .isModal : [],
                )
                // Report the footprint the non-modal HUD occupies so `RootView`
                // can inset the app content behind it.
                .preference(
                    key: DeveloperOverlayInsetKey.self,
                    value: appContentInsets(in: proxy.size),
                )
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

        private func openTool(_ tool: DeveloperTool) {
            withAnimation(stylesheet.developerOverlay.presentationAnimation) {
                model.open(tool)
            }
        }

        private func dragGesture(in proxy: GeometryProxy) -> some Gesture {
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    isDraggingButton = true
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
            let edgeInset = stylesheet.developerOverlay.edgeInset
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
            let minX = model.corner.isLeading
                ? style.edgeInset
                : container.width - style.edgeInset - menuWidth
            return CGRect(x: minX, y: startY, width: menuWidth, height: height)
        }

        private func panel(
            tool: DeveloperTool,
            isFullScreen: Bool,
            in proxy: GeometryProxy,
        ) -> some View {
            let style = stylesheet.developerOverlay
            let layout = displayedLayout(in: proxy.size)
            let size = isFullScreen ? fullScreenSize(in: proxy.size) : layout.size
            let center = isFullScreen
                ? CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
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
                    moveWindow(by: translation, ended: ended, in: proxy.size)
                },
                onResize: { translation, ended in
                    resizeWindow(by: translation, ended: ended, in: proxy.size)
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
        private func appContentInsets(in container: CGSize) -> EdgeInsets {
            guard case .floating = model.presentation else { return EdgeInsets() }
            let style = stylesheet.developerOverlay
            return DeveloperOverlayModel.contentInsets(
                for: displayedLayout(in: container),
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
            whereSnapshot(name: "MenuBottomTrailing", configurations: .phoneLightDark) {
                DeveloperOverlayPreview(presentation: .menu)
            }
            whereSnapshot(
                name: "MenuTopLeading",
                configurations: SnapshotConfiguration.combinations(devices: [.iPhone]),
            ) {
                DeveloperOverlayPreview(presentation: .menu, corner: .topLeading)
            }
            whereSnapshot(
                name: "SelectedTool",
                configurations: SnapshotConfiguration.combinations(devices: [.iPhone]),
            ) {
                DeveloperOverlayPreview(presentation: .floating(.regionMap))
            }
        }
    }

    #Preview {
        DeveloperOverlay.snapshotPreviews
    }
#endif
