import SwiftUI

/// The app-icon picker: a two-column grid of options. Tapping a cell opens a
/// full-screen preview (matched zoom transition) where the user confirms the
/// change. Pushed from `SettingsView`.
struct AppIconView: View {
    @State private var model: AppIconModel
    @State private var previewedOption: AppIconOption?
    @Namespace private var iconNamespace

    @MainActor
    init(model: AppIconModel = AppIconModel()) {
        _model = State(initialValue: model)
    }

    private let columns = [
        GridItem(.flexible(), spacing: UIConstants.Spacings.xxLarge),
        GridItem(.flexible(), spacing: UIConstants.Spacings.xxLarge),
    ]

    var body: some View {
        @Bindable var model = model

        ScrollView {
            LazyVGrid(columns: columns, spacing: UIConstants.Spacings.xxxLarge) {
                ForEach(model.options) { option in
                    cell(for: option)
                }
            }
            .padding(UIConstants.Spacings.xxLarge)
        }
        .navigationTitle(Strings.appIconTitle)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $previewedOption) { option in
            AppIconPreviewView(option: option, model: model, namespace: iconNamespace)
        }
        .alert(Strings.appIconErrorTitle, isPresented: $model.isShowingError) {
            Button(Strings.commonOK, role: .cancel) {}
        } message: {
            Text(model.applyError ?? "")
        }
    }

    private func cell(for option: AppIconOption) -> some View {
        let isSelected = model.isSelected(option)
        return Button {
            previewedOption = option
        } label: {
            VStack(spacing: UIConstants.Spacings.large) {
                AppIconImage(name: option.previewImageName, size: UIConstants.Size.appIconGrid)
                    .matchedTransitionSource(id: option.id, in: iconNamespace)

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
}

/// A rounded app-icon thumbnail rendered from the WhereUI preview catalog,
/// using iOS's continuous-corner squircle proportion so it reads as an icon.
struct AppIconImage: View {
    let name: String
    let size: CGFloat

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
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5),
            )
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            AppIconView(model: .preview())
        }
    }
#endif
