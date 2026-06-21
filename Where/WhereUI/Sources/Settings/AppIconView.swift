import SwiftUI

/// The app-icon picker: a grid of options that flexes with the container width
/// (two columns on phones, more on wider displays — see `AppIconLayout`).
/// Tapping a cell opens a full-screen preview (matched zoom transition) where
/// the user confirms the change. Presented as a sheet from `SettingsView`, so
/// it owns its navigation bar and a Done button to dismiss.
struct AppIconView: View {
    @State private var model: AppIconModel
    @State private var previewedOption: AppIconOption?
    @Namespace private var iconNamespace
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @MainActor
    init(model: AppIconModel = AppIconModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let metrics = AppIconLayout.gridMetrics(containerWidth: proxy.size.width)
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
            }
            .navigationTitle(Strings.appIconTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.commonDone) { dismiss() }
                }
            }
        }
        .fullScreenCover(item: $previewedOption) { option in
            AppIconPreviewView(
                option: option,
                model: model,
                namespace: iconNamespace,
                initialMode: colorScheme,
            )
        }
    }

    private func gridColumns(count: Int) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: UIConstants.Spacings.xxLarge),
            count: count,
        )
    }

    private func cell(for option: AppIconOption, iconSize: CGFloat) -> some View {
        let isSelected = model.isSelected(option)
        return Button {
            previewedOption = option
        } label: {
            VStack(spacing: UIConstants.Spacings.large) {
                AppIconImage(name: option.previewImageName, size: iconSize)
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
        AppIconView(model: .preview())
    }
#endif
