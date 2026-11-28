#if DEBUG
    import SFSafeSymbols
    import SwiftUI

    struct DeveloperOverlayLayout: View {
        let geometry: AdaptivePaneGeometry
        let model: DeveloperOverlayModel
        let openDestination: (DeveloperDestination) -> Void
        let configureDemo: () -> Void

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
        // Gesture points and reserved-region frames use physical container coordinates.
        @Environment(\.layoutDirection) private var layoutDirection

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
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
                    DeveloperMenuDismissButton(action: closeMenu)
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
                    DeveloperToolPanel(
                        tool: tool,
                        isFullScreen: model.presentation.isFullScreen,
                        container: container,
                        layout: displayedLayout(in: container),
                        onToggleFullScreen: {
                            withAnimation(style.presentationAnimation) { model.toggleFullScreen() }
                        },
                        onClose: {
                            withAnimation(style.presentationAnimation) { model.closeTool() }
                        },
                        onMove: { moveWindow(by: $0, ended: $1, in: container) },
                        onResize: { resizeWindow(by: $0, ended: $1, in: container) },
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

    private struct DeveloperMenuDismissButton: View {
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
    }

    #Preview { DeveloperOverlayPreview(presentation: .floating(.regionMap)) }

    /// The floating developer launcher.
    ///
    /// A semantic button so VoiceOver and Voice Control receive the same
    /// interaction as touch users. Its wrench becomes a close glyph while the
    /// accordion is open; dragging remains owned by ``DeveloperOverlay``.
    ///
    /// The stylesheet scales its diameter. The overlay measures the rendered
    /// size for its drag bounds.
    private struct DeveloperOverlayButton: View {
        let isMenuPresented: Bool
        let action: () -> Void

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            let style = stylesheet.developerOverlay.launcher
            Button(action: action) {
                Image(systemSymbol: isMenuPresented ? .xmark : .wrenchAndScrewdriver)
                    .font(.system(size: style.diameter * style.glyphRatio, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: style.diameter, height: style.diameter)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .contentShape(Circle())
            .shadow(color: style.shadowColor, radius: style.shadowRadius, y: style.shadowOffsetY)
            .accessibilityLabel(
                isMenuPresented
                    ? String(localized: .developerMenuClose)
                    : String(localized: .developerButtonLabel),
            )
        }
    }

    private struct DeveloperOverlayButtonPreview: View {
        let isMenuPresented: Bool

        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [.teal, .orange, .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                )
                .ignoresSafeArea()

                DeveloperOverlayButton(isMenuPresented: isMenuPresented, action: {})
            }
            .whereBroadwayRoot()
        }
    }

    #Preview("Light") {
        DeveloperOverlayButtonPreview(isMenuPresented: false).environment(\.colorScheme, .light)
    }

    #Preview("Dark") {
        DeveloperOverlayButtonPreview(isMenuPresented: true).environment(\.colorScheme, .dark)
    }
#endif
