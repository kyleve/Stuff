import SwiftUI

/// Full-screen preview of a single app icon, presented as a zoom transition
/// from the picker grid. A close button (top-left) dismisses; Change (top-right)
/// applies the icon; a light/dark selector (bottom) flips the whole preview —
/// background and icon art — so the user sees both appearance variants.
struct AppIconPreviewView: View {
    let option: AppIconOption
    @Bindable var model: AppIconModel
    let namespace: Namespace.ID

    @Environment(\.dismiss) private var dismiss
    @State private var previewMode: ColorScheme

    /// `initialMode` seeds the light/dark selector from the system appearance so
    /// a dark-mode user opens straight into the dark preview (no light flash).
    init(
        option: AppIconOption,
        model: AppIconModel,
        namespace: Namespace.ID,
        initialMode: ColorScheme = .light,
    ) {
        self.option = option
        _model = Bindable(wrappedValue: model)
        self.namespace = namespace
        _previewMode = State(initialValue: initialMode)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: UIConstants.Spacings.xxxLarge) {
                    Spacer(minLength: 0)
                    previewStack
                    Spacer(minLength: 0)
                    appearancePicker
                }
                .padding(UIConstants.Spacings.xxxLarge)
            }
            .navigationTitle(option.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Strings.appIconClose)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Strings.appIconChange) {
                        Task {
                            // Stay open on failure so the alert is visible; the
                            // picker beneath would race the cover's dismissal.
                            if await model.apply(option) {
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(model.isSelected(option) || !model.supportsAlternateIcons)
                }
            }
        }
        .environment(\.colorScheme, previewMode)
        .navigationTransition(.zoom(sourceID: option.id, in: namespace))
        .alert(Strings.appIconErrorTitle, isPresented: $model.isShowingError) {
            Button(Strings.commonOK, role: .cancel) {}
        } message: {
            Text(model.applyError ?? "")
        }
    }

    private var previewStack: some View {
        VStack(spacing: UIConstants.Spacings.xxxLarge) {
            iconBlock(size: UIConstants.Size.appIconPreviewLarge, caption: Strings.appIconSizeLarge)
            iconBlock(size: UIConstants.Size.appIconPreviewSmall, caption: Strings.appIconSizeSmall)
        }
    }

    private func iconBlock(size: CGFloat, caption: String) -> some View {
        VStack(spacing: UIConstants.Spacings.regular) {
            AppIconImage(name: option.previewImageName, size: size)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var appearancePicker: some View {
        Picker(Strings.appIconAppearanceLabel, selection: $previewMode) {
            Text(Strings.appIconAppearanceLight).tag(ColorScheme.light)
            Text(Strings.appIconAppearanceDark).tag(ColorScheme.dark)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

#if DEBUG
    private struct AppIconPreviewHost: View {
        @Namespace private var namespace

        var body: some View {
            AppIconPreviewView(
                option: AppIconOption(
                    id: AppIconID("classic"),
                    displayName: "Classic",
                    alternateIconName: nil,
                    previewImageName: "AppIconClassic",
                ),
                model: .preview(),
                namespace: namespace,
            )
        }
    }

    #Preview {
        AppIconPreviewHost()
    }
#endif
