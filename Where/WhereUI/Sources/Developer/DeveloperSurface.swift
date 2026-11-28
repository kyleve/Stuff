#if DEBUG
    import BroadwayUI
    import PeriscopeTools
    import SFSafeSymbols
    import SwiftUI
    import WhereCore

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
                DeveloperSurfaceControlStrip(
                    isFullScreen: isFullScreen,
                    onClose: onClose,
                    onToggleFullScreen: onToggleFullScreen,
                    onMove: onMove,
                )

                Divider().opacity(0.5)

                DeveloperToolView(tool: tool)
                    .safeAreaPadding(
                        .bottom,
                        isFullScreen ? 0 : panel.resizeGripClearance,
                    )
            }
            .overlay(alignment: .bottomTrailing) {
                if isFullScreen == false {
                    DeveloperSurfaceResizeHandle(onResize: onResize)
                }
            }
            // The HUD is intentionally compact; tool navigation still uses
            // semantic text styles within this bounded developer-only surface.
            .dynamicTypeSize(.small)
            .bContentSizeCategory(.small)
        }
    }

    private struct DeveloperSurfaceControlStrip: View {
        let isFullScreen: Bool
        let onClose: () -> Void
        let onToggleFullScreen: () -> Void
        let onMove: (CGSize, Bool) -> Void

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            let panel = stylesheet.developerOverlay.panel
            HStack(spacing: 0) {
                DeveloperSurfaceCloseButton(action: onClose)

                Spacer(minLength: 0)

                if isFullScreen {
                    Color.clear
                        .frame(width: 1, height: 1)
                } else {
                    DeveloperSurfaceDragHandle(onMove: onMove)
                }

                Spacer(minLength: 0)

                DeveloperSurfaceSizeButton(isFullScreen: isFullScreen, action: onToggleFullScreen)
            }
            .font(.title3)
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(.horizontal, panel.controlHorizontalPadding)
            .padding(.vertical, panel.controlVerticalPadding)
        }
    }

    private struct DeveloperSurfaceCloseButton: View {
        let action: () -> Void

        var body: some View {
            Button(
                String(localized: .developerClose),
                systemSymbol: .xmarkCircleFill,
                action: action,
            )
            .labelStyle(.iconOnly)
            .symbolRenderingMode(.hierarchical)
        }
    }

    private struct DeveloperSurfaceSizeButton: View {
        let isFullScreen: Bool
        let action: () -> Void

        var body: some View {
            Button(
                isFullScreen
                    ? String(localized: .developerCollapse)
                    : String(localized: .developerExpand),
                systemSymbol: isFullScreen
                    ? .arrowDownRightAndArrowUpLeft
                    : .arrowUpLeftAndArrowDownRight,
                action: action,
            )
            .labelStyle(.iconOnly)
        }
    }

    private struct DeveloperSurfaceDragHandle: View {
        let onMove: (CGSize, Bool) -> Void

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            let panel = stylesheet.developerOverlay.panel
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
    }

    #Preview {
        DeveloperOverlayPreview(presentation: .floating(.regionMap))
    }

    /// Hosts developer tools in native navigation, except the lab’s independent app scene.
    ///
    /// The lightweight accordion owns routing; this surface owns only the ambient
    /// stack each tool expects. Making the selected tool the stack root removes
    /// the redundant Developer list title/back button while preserving every
    /// tool's own drill-ins and toolbar.
    ///
    /// The optional dependencies can disappear if the app resets while a tool is
    /// open. That renders an honest unavailable state rather than retaining stale
    /// session resources or crashing.
    private struct DeveloperToolView: View {
        let tool: DeveloperTool

        var body: some View {
            if tool == .deviceLayoutLab {
                // An ancestor stack suppresses the embedded app's navigation content.
                DeveloperToolContent(tool: tool)
            } else {
                NavigationStack { DeveloperToolContent(tool: tool) }
            }
        }
    }

    #Preview("Region map") {
        DeveloperToolView(tool: .regionMap)
            .environment(PreviewSupport.loadedModel())
            .environment(PreviewSupport.loadedSession())
    }

    #Preview("Crash testing") {
        DeveloperToolView(tool: .crashTesting)
    }

    private struct DeveloperToolContent: View {
        let tool: DeveloperTool

        var body: some View {
            switch tool {
                case .crashTesting:
                    DeveloperCrashTestingView()

                case .logs:
                    DeveloperLogToolContent(tool: tool)

                case .openSpans:
                    OpenSpansView(system: .shared)

                case .regionMap:
                    RegionMapView()

                case .deviceLayoutLab:
                    DeviceLayoutLabView()
            }
        }
    }

    private struct DeveloperSurfaceResizeHandle: View {
        let onResize: (CGSize, Bool) -> Void

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            let panel = stylesheet.developerOverlay.panel
            Image(systemSymbol: .arrowDownRight)
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
#endif
