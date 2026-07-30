#if DEBUG
    import SwiftUI

    /// Chrome and navigation host for one selected developer tool.
    ///
    /// The control strip stays outside the tool's `NavigationStack`, so close,
    /// move, resize, and full-screen controls remain reachable through every
    /// drill-in.
    struct DeveloperSurface: View {
        let tool: DeveloperTool
        let isFullScreen: Bool
        let onToggleFullScreen: () -> Void
        let onClose: () -> Void
        /// Reports the window drag handle's translation; `ended` marks the commit.
        let onMove: (CGSize, _ ended: Bool) -> Void
        /// Reports the resize grip's translation; `ended` marks the commit.
        let onResize: (CGSize, _ ended: Bool) -> Void

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            let panel = stylesheet.developerOverlay.panel
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Button(
                        String(localized: .developerClose),
                        systemImage: "xmark.circle.fill",
                        action: onClose,
                    )
                    .labelStyle(.iconOnly)
                    .symbolRenderingMode(.hierarchical)

                    Spacer(minLength: 0)

                    if isFullScreen {
                        Color.clear
                            .frame(width: 1, height: 1)
                    } else {
                        Capsule()
                            .fill(.secondary)
                            .frame(
                                width: panel.dragHandleSize.width,
                                height: panel.dragHandleSize.height,
                            )
                            .frame(maxWidth: .infinity, minHeight: panel.dragHandleMinHeight)
                            .contentShape(Rectangle())
                            // Global coordinates keep the translation anchored
                            // while the window itself moves beneath the gesture.
                            .gesture(
                                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                    .onChanged { onMove($0.translation, false) }
                                    .onEnded { onMove($0.translation, true) },
                            )
                            .accessibilityLabel(String(localized: .developerDragHandle))
                    }

                    Spacer(minLength: 0)

                    Button(
                        isFullScreen
                            ? String(localized: .developerCollapse)
                            : String(localized: .developerExpand),
                        systemImage: isFullScreen
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right",
                        action: onToggleFullScreen,
                    )
                    .labelStyle(.iconOnly)
                }
                .font(.title3)
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .padding(.horizontal, panel.controlHorizontalPadding)
                .padding(.vertical, panel.controlVerticalPadding)

                Divider().opacity(0.5)

                DeveloperToolView(tool: tool)
                    .safeAreaPadding(
                        .bottom,
                        isFullScreen ? 0 : panel.resizeGripClearance,
                    )
            }
            .overlay(alignment: .bottomTrailing) {
                if isFullScreen == false {
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: panel.resizeIconSize, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: panel.resizeGripSize, height: panel.resizeGripSize)
                        .contentShape(Rectangle())
                        // Global coordinates keep the translation anchored while
                        // the bottom-trailing corner grows beneath the gesture.
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { onResize($0.translation, false) }
                                .onEnded { onResize($0.translation, true) },
                        )
                        .accessibilityLabel(String(localized: .developerResizeHandle))
                }
            }
            // The HUD is intentionally compact; tool navigation still uses
            // semantic text styles within this bounded developer-only surface.
            .dynamicTypeSize(.small)
        }
    }

    #Preview {
        DeveloperOverlayPreview(presentation: .floating(.regionMap))
    }
#endif
