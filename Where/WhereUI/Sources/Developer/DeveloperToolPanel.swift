#if DEBUG
    import SwiftUI

    struct DeveloperToolPanel: View {
        let tool: DeveloperTool
        let isFullScreen: Bool
        let container: CGSize
        let layout: DeveloperOverlayModel.FloatingLayout
        let onToggleFullScreen: () -> Void
        let onClose: () -> Void
        let onMove: (CGSize, Bool) -> Void
        let onResize: (CGSize, Bool) -> Void

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            let style = stylesheet.developerOverlay
            let size = isFullScreen ? fullScreenSize(in: container) : layout.size
            let center = isFullScreen
                ? CGPoint(x: container.width / 2, y: container.height / 2)
                : layout.center
            let shape = RoundedRectangle(cornerRadius: style.panel.cornerRadius)
            DeveloperSurface(
                tool: tool,
                isFullScreen: isFullScreen,
                onToggleFullScreen: onToggleFullScreen,
                onClose: onClose,
                onMove: onMove,
                onResize: onResize,
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

        private func fullScreenSize(in container: CGSize) -> CGSize {
            let inset = stylesheet.developerOverlay.panel.fullScreenInset
            return CGSize(
                width: max(container.width - inset * 2, 0),
                height: max(container.height - inset * 2, 0),
            )
        }
    }

    #Preview { DeveloperOverlayPreview(presentation: .floating(.regionMap)) }
#endif
