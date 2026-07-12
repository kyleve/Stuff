#if DEBUG
    import SwiftUI
    import UIKit

    /// A global, DEBUG-only developer surface that floats above the entire app.
    ///
    /// Collapsed, it's a small draggable button (``DeveloperOverlayButton``) that
    /// snaps to the nearest corner. Tapping expands it into a Picture-in-Picture
    /// style floating panel hosting ``DeveloperToolsView``; from there it grows to
    /// full screen and shrinks back. In the collapsed and floating states the rest
    /// of the app stays interactive behind it — only the button/panel capture
    /// touches — so the tools are reachable from anywhere, including before login.
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

        private let edgeInset: CGFloat = 16
        private let panelCornerRadius: CGFloat = 22

        var body: some View {
            GeometryReader { proxy in
                ZStack {
                    // A full-bleed backdrop only in full screen; in the floating
                    // (PiP) state the app behind stays visible and usable.
                    if model.presentation == .fullScreen {
                        Color(.systemBackground)
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
                        model.corner = newCorner
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
            let size = panelSize(in: proxy.size, fullScreen: isFullScreen)
            let radius = isFullScreen ? 0 : panelCornerRadius
            return DeveloperSurface(
                isFullScreen: isFullScreen,
                onToggleFullScreen: {
                    withAnimation(.snappy(duration: 0.3)) { model.toggleFullScreen() }
                },
                onClose: { model.close() },
            )
            .frame(width: size.width, height: size.height)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(isFullScreen ? 0 : 0.3), radius: 20, y: 6)
            // Full screen covers the app, so it becomes an accessibility modal:
            // VoiceOver ignores everything behind it and stays trapped in the
            // tools. The floating (PiP) panel stays non-modal — the app behind is
            // still reachable — matching its visible, tap-through behavior.
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(isFullScreen ? .isModal : [])
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .transition(.scale(scale: 0.12, anchor: .bottomTrailing).combined(with: .opacity))
        }

        private func panelSize(in container: CGSize, fullScreen: Bool) -> CGSize {
            guard !fullScreen else { return container }
            let width = min(container.width - edgeInset * 2, 420)
            let height = min(container.height * 0.62, 620)
            return CGSize(width: max(width, 0), height: max(height, 0))
        }
    }

    /// The chrome + content of the expanded panel: a slim control strip (close /
    /// resize) above the tools. The strip lives here — outside
    /// ``DeveloperToolsView``'s own `NavigationStack` — so it stays visible no
    /// matter how deep the user navigates into a tool.
    private struct DeveloperSurface: View {
        let isFullScreen: Bool
        let onToggleFullScreen: () -> Void
        let onClose: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                controlBar
                Divider()
                DeveloperToolsView()
            }
        }

        private var controlBar: some View {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel(String(localized: .developerClose))

                Spacer()

                Button(action: onToggleFullScreen) {
                    Image(systemName: isFullScreen
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel(isFullScreen ? String(localized: .developerCollapse) :
                    String(localized: .developerExpand))
            }
            .font(.title3)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
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
