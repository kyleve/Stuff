import SwiftUI

/// The app-icon picker. A grid of options that flexes with the container width
/// (two columns on phones, more on wider displays — see `AppIconLayout`).
/// Tapping a cell slides a preview panel up from the bottom over the dimmed
/// grid: the panel's background reflects a light/dark mode you toggle by tapping
/// the icon, and a Set button applies it. Presented as a sheet from
/// `SettingsView`, so it owns its navigation bar and a Done button.
struct AppIconView: View {
    @State private var model: AppIconModel
    @State private var preview: AppIconOption?
    @State private var previewMode: ColorScheme = .light
    @State private var appearanceToggles = 0
    @State private var dragOffset: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @MainActor
    init(model: AppIconModel = AppIconModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let grid = AppIconLayout.gridMetrics(containerWidth: proxy.size.width)
                let previewIconSize = AppIconLayout.previewIconSize(containerSize: proxy.size)
                ZStack(alignment: .bottom) {
                    grids(metrics: grid)

                    if preview != nil {
                        scrim
                    }

                    if let option = preview {
                        previewPanel(for: option, iconSize: previewIconSize)
                            .transition(.move(edge: .bottom))
                    }
                }
                .navigationTitle(Strings.appIconTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Strings.commonDone) { dismiss() }
                    }
                }
            }
        }
        .sensoryFeedback(trigger: preview) { _, new in
            new == nil ? nil : .impact(weight: .light)
        }
        .sensoryFeedback(.selection, trigger: appearanceToggles)
        .sensoryFeedback(.success, trigger: model.selectedID)
        .alert(Strings.appIconErrorTitle, isPresented: $model.isShowingError) {
            Button(Strings.commonOK, role: .cancel) {}
        } message: {
            Text(model.applyError ?? "")
        }
    }

    private func grids(metrics: AppIconGridMetrics) -> some View {
        ScrollView {
            LazyVGrid(
                columns: gridColumns(count: metrics.columnCount),
                spacing: UIConstants.Spacings.xxxLarge,
            ) {
                ForEach(model.options) { option in
                    cell(for: option, iconSize: metrics.iconSize)
                }
            }
            .padding(UIConstants.Spacings.xxLarge)
        }
        .scrollDisabled(preview != nil)
    }

    private func gridColumns(count: Int) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: UIConstants.Spacings.xxLarge),
            count: count,
        )
    }

    private func cell(for option: AppIconOption, iconSize: CGFloat) -> some View {
        let isSelected = model.isSelected(option)
        // Dim this cell's icon while its own panel is up so the grid reads as
        // backgrounded without fully hiding the icon already enlarged in the
        // panel. It fades back as the panel slides away (the flip rides the same
        // `.snappy` animation that drives `preview`).
        let isPreviewing = preview?.id == option.id
        return Button {
            select(option)
        } label: {
            VStack(spacing: UIConstants.Spacings.large) {
                AppIconImage(name: option.previewImageName, size: iconSize)
                    .opacity(isPreviewing ? 0.5 : 1)

                HStack(spacing: UIConstants.Spacings.small) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(option.displayName)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                }
                .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(option.displayName)
        .accessibilityValue(isSelected ? Strings.appIconCurrent : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var scrim: some View {
        Rectangle()
            .fill(.black.opacity(0.25))
            .ignoresSafeArea()
            .transition(.opacity)
            .onTapGesture { dismissPreview() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Strings.commonDone)
            .accessibilityAction { dismissPreview() }
    }

    private func previewPanel(for option: AppIconOption, iconSize: CGFloat) -> some View {
        VStack(spacing: UIConstants.Spacings.xLarge) {
            Capsule()
                .fill(.secondary.opacity(0.5))
                .frame(width: 40, height: 5)
                .padding(.top, UIConstants.Spacings.medium)

            Button {
                toggleAppearance()
            } label: {
                previewIcon(for: option, size: iconSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(option.displayName)
            .accessibilityValue(previewMode == .dark ? Strings.appIconAppearanceDark : Strings
                .appIconAppearanceLight)
            .accessibilityHint(Strings.appIconAppearanceHint)

            VStack(spacing: UIConstants.Spacings.xSmall) {
                Text(option.displayName)
                    .font(.title3.weight(.semibold))
                Text(Strings.appIconAppearanceHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                apply(option)
            } label: {
                Text(Strings.appIconSet)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isSelected(option) || !model.supportsAlternateIcons)
        }
        .padding(.horizontal, UIConstants.Spacings.xxxLarge)
        .padding(.bottom, UIConstants.Spacings.xxLarge)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: UIConstants.CornerRadius.card,
                topTrailingRadius: UIConstants.CornerRadius.card,
                style: .continuous,
            )
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.18), radius: 18, y: -4)
            .ignoresSafeArea(edges: .bottom)
        }
        .environment(\.colorScheme, previewMode)
        .offset(y: max(dragOffset, 0))
        .gesture(dragToDismiss)
    }

    /// The tappable preview icon. Tapping toggles light/dark, which crossfades
    /// the art and background while this plays a quick scale-down-then-bounce.
    /// Keyed off `appearanceToggles` so the bounce only fires on a real tap, not
    /// when the panel first opens.
    private func previewIcon(for option: AppIconOption, size: CGFloat) -> some View {
        AppIconImage(name: option.previewImageName, size: size)
            .keyframeAnimator(initialValue: 1.0, trigger: appearanceToggles) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(0.82, duration: 0.12)
                    SpringKeyframe(1.0, duration: 0.42, spring: .bouncy)
                }
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
        appearanceToggles += 1
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
    let name: String
    let size: CGFloat
    var bordered = true

    private var cornerRadius: CGFloat {
        // ~22.37% of the side length is Apple's icon superellipse proportion.
        size * 0.2237
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

#if DEBUG
    #Preview {
        AppIconView(model: .preview())
    }
#endif
