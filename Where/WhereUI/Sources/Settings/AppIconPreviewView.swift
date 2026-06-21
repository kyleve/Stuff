import SwiftUI

/// Full-screen preview of a single app icon, presented as a zoom transition
/// from the picker grid. A close button (top-left) dismisses; Change (top-right)
/// applies the icon; a light/dark selector (bottom) flips the whole preview —
/// background and icon art — so the user sees both appearance variants.
struct AppIconPreviewView: View {
    let option: AppIconOption
    let model: AppIconModel
    let namespace: Namespace.ID

    @Environment(\.dismiss) private var dismiss
    @State private var previewMode: ColorScheme = .light

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: UIConstants.Spacings.xxxLarge) {
                topBar
                Spacer(minLength: 0)
                previewStack
                Spacer(minLength: 0)
                appearancePicker
            }
            .padding(UIConstants.Spacings.xxxLarge)
        }
        .environment(\.colorScheme, previewMode)
        .navigationTransition(.zoom(sourceID: option.id, in: namespace))
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(
                        width: UIConstants.Size.statusIconWidth,
                        height: UIConstants.Size.statusIconWidth,
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.appIconClose)

            Spacer()

            Button(Strings.appIconChange) {
                Task {
                    await model.apply(option)
                    dismiss()
                }
            }
            .font(.headline)
            .fontWeight(.semibold)
            .disabled(model.isSelected(option) || !model.supportsAlternateIcons)
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
