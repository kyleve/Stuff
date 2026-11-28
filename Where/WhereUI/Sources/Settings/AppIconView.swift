import BroadwayCore
import BroadwayUI
import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// The app-icon picker. A grid of options that flexes with the container width
/// (two columns on phones, more on wider displays — see `AppIconLayout`).
/// Tapping a cell slides a preview panel up from the bottom over the dimmed
/// grid: the panel's background reflects a light/dark mode you toggle by tapping
/// the icon, and a Set button applies it. Presented as a sheet from the
/// Appearance sub-screen, so it owns its navigation bar and a Done button.
struct AppIconView: View {
    @State private var model: AppIconModel
    @State private var preview: AppIconOption?
    @State private var previewMode: ColorScheme = .light
    @State private var appearanceToggleTrigger = EventTrigger()
    @State private var dragOffset: CGFloat = 0
    // Seeds user-editable preview state at selection time; that state is not a slice input.
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.stylesheet) private var stylesheet

    @MainActor
    init(primaryAppIconName: String) {
        _model = State(initialValue: AppIconModel(
            primaryAppIconName: primaryAppIconName,
        ))
    }

    @MainActor
    init(model: AppIconModel) {
        _model = State(initialValue: model)
    }

    private var appIcon: WhereStylesheet.AppIconStyle {
        stylesheet.appIcon
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let grid = AppIconLayout.gridMetrics(
                    containerWidth: proxy.size.width,
                    style: appIcon,
                )
                let previewIconSize = AppIconLayout.previewIconSize(
                    containerSize: proxy.size,
                    style: appIcon,
                )
                ZStack(alignment: .bottom) {
                    AppIconGrid(
                        model: model,
                        metrics: grid,
                        previewID: preview?.id,
                        select: select,
                    )

                    if preview != nil {
                        AppIconPreviewScrim(dismissPreview: dismissPreview)
                    }

                    if let option = preview {
                        AppIconPreviewPanel(
                            option: option,
                            iconSize: previewIconSize,
                            previewMode: previewMode,
                            appearanceToggleTrigger: appearanceToggleTrigger,
                            canApply: !model.isSelected(option) && model.supportsAlternateIcons,
                            toggleAppearance: toggleAppearance,
                            apply: { apply(option) },
                        )
                        .offset(y: max(dragOffset, 0))
                        .gesture(dragToDismiss)
                        .transition(.move(edge: .bottom))
                    }
                }
                .navigationTitle(String(localized: .appIconTitle))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: .commonDone)) { dismiss() }
                    }
                }
            }
        }
        .sensoryFeedback(trigger: preview) { _, new in
            new == nil ? nil : .impact(weight: .light)
        }
        .sensoryFeedback(.selection, trigger: appearanceToggleTrigger)
        .sensoryFeedback(.success, trigger: model.selectedID)
        .alert(String(localized: .appIconErrorTitle), isPresented: $model.isShowingError) {
            Button(String(localized: .commonOk), role: .cancel) {}
        } message: {
            Text(model.applyError ?? "")
        }
    }

    private var dragToDismiss: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let shouldDismiss = value.translation.height > 80
                    || value.predictedEndTranslation.height > 200
                if shouldDismiss {
                    dismissPreview()
                } else {
                    withAnimation(.snappy) { dragOffset = 0 }
                }
            }
    }

    private func select(_ option: AppIconOption) {
        previewMode = colorScheme
        withAnimation(.snappy) {
            dragOffset = 0
            preview = option
        }
    }

    private func dismissPreview() {
        withAnimation(.snappy) {
            preview = nil
            dragOffset = 0
        }
    }

    private func toggleAppearance() {
        appearanceToggleTrigger.fire()
        withAnimation(.easeInOut(duration: 0.3)) {
            previewMode = previewMode == .dark ? .light : .dark
        }
    }

    private func apply(_ option: AppIconOption) {
        Task {
            // Only dismiss on success; a failure keeps the panel up so the
            // error alert reads against the icon the user tried to set.
            if await model.apply(option) {
                dismissPreview()
            }
        }
    }
}

/// A rounded app-icon thumbnail rendered from the WhereUI preview catalog,
/// using iOS's continuous-corner squircle proportion so it reads as an icon.
///
/// The hairline `separator` border keeps a thumbnail legible against the
/// picker's system background; pass `bordered: false` where the icon is the
/// hero on its own backdrop (e.g. the launch splash) and the border would read
/// as a stray outline.
struct AppIconImage: View {
    /// Fraction of an icon's side length used for its rounded corners — Apple's
    /// continuous-corner superellipse proportion (~22.37%). Shared so every
    /// icon rendering (the picker thumbnail here, the launch splash hero) reads
    /// as the same squircle.
    static let cornerRadiusRatio: CGFloat = 0.2237

    let name: String
    let size: CGFloat
    var bordered = true

    private var cornerRadius: CGFloat {
        size * Self.cornerRadiusRatio
    }

    var body: some View {
        Image(name, bundle: .module)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                }
            }
            .accessibilityHidden(true)
    }
}

private struct AppIconGrid: View {
    let model: AppIconModel
    let metrics: AppIconGridMetrics
    let previewID: AppIconID?
    let select: (AppIconOption) -> Void

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: gridColumns(count: metrics.columnCount),
                spacing: appIcon.gridSpacing,
            ) {
                ForEach(model.options) { option in
                    AppIconSelectionButton(
                        option: option,
                        iconSize: metrics.iconSize,
                        isSelected: model.isSelected(option),
                        isPreviewing: previewID == option.id,
                        select: { select(option) },
                    )
                }
            }
            .padding(appIcon.gridPadding)
        }
        .scrollDisabled(previewID != nil)
    }

    private func gridColumns(count: Int) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: appIcon.columnSpacing),
            count: count,
        )
    }

    private var appIcon: WhereStylesheet.AppIconStyle {
        stylesheet.appIcon
    }
}

private struct AppIconPreviewScrim: View {
    let dismissPreview: () -> Void

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Rectangle()
            .fill(stylesheet.appIcon.scrim)
            .ignoresSafeArea()
            .transition(.opacity)
            .onTapGesture { dismissPreview() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(String(localized: .commonDone))
            .accessibilityAction { dismissPreview() }
    }
}

private struct AppIconPreviewPanel: View {
    let option: AppIconOption
    let iconSize: CGFloat
    let previewMode: ColorScheme
    let appearanceToggleTrigger: EventTrigger
    let canApply: Bool
    let toggleAppearance: () -> Void
    let apply: () -> Void

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let appIcon = stylesheet.appIcon
        VStack(spacing: appIcon.panel.spacing) {
            AppIconPreviewGrabber(style: appIcon.panel)

            AppIconPreviewModeButton(
                option: option,
                iconSize: iconSize,
                previewMode: previewMode,
                appearanceToggleTrigger: appearanceToggleTrigger,
                toggleAppearance: toggleAppearance,
            )

            AppIconPreviewDescription(option: option, style: appIcon.panel)

            AppIconSetButton(canApply: canApply, apply: apply)
        }
        .padding(.horizontal, appIcon.panel.horizontalPadding)
        .padding(.bottom, appIcon.panel.bottomPadding)
        .frame(maxWidth: .infinity)
        .background { AppIconPreviewBackground(style: appIcon.panel) }
        .environment(\.colorScheme, previewMode)
        .bMode(.init(previewMode))
    }
}

private struct AppIconPreviewGrabber: View {
    let style: WhereStylesheet.AppIconStyle.PanelStyle

    var body: some View {
        Capsule()
            .fill(.secondary.opacity(style.grabberOpacity))
            .frame(
                width: style.grabberSize.width,
                height: style.grabberSize.height,
            )
            .padding(.top, style.grabberTopPadding)
    }
}

private struct AppIconPreviewDescription: View {
    let option: AppIconOption
    let style: WhereStylesheet.AppIconStyle.PanelStyle

    var body: some View {
        VStack(spacing: style.textSpacing) {
            Text(option.displayName)
                .font(.title3.weight(.semibold))
            Text(String(localized: .appIconAppearanceHint))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct AppIconPreviewBackground: View {
    let style: WhereStylesheet.AppIconStyle.PanelStyle

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: style.cornerRadius,
            topTrailingRadius: style.cornerRadius,
            style: .continuous,
        )
        .fill(style.background)
        .shadow(
            color: style.shadowColor,
            radius: style.shadowRadius,
            y: style.shadowOffsetY,
        )
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct AppIconSetButton: View {
    let canApply: Bool
    let apply: () -> Void

    var body: some View {
        Button {
            apply()
        } label: {
            Text(String(localized: .appIconSet))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canApply)
    }
}

#if DEBUG
    extension AppIconView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentScreenRepresentative,
                settle: .immediate,
            ) {
                NavigationStack {
                    AppIconView(model: .preview())
                }
            }
        }
    }

    #Preview("Classic") {
        AppIconImage(name: "AppIconClassic", size: 60)
            .padding()
    }

    #Preview {
        AppIconView.snapshotPreviews
    }
#endif

#if DEBUG
    extension AppIconView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            AppIconView.self,
            title: "App Icon",
        )
    }
#endif
