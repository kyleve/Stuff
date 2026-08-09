import SwiftUI

/// Shows the icon iOS currently has selected, sourced from the same manifest and
/// live system value as the full app-icon picker.
struct FeatureAppIconPreview: View {
    let model: AppIconModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: stylesheet.featureDiscovery.cardSpacing) {
                Label(
                    String(localized: .settingsExplorePersonalizationIconTitle),
                    systemImage: "app.badge",
                )
                .font(.headline)

                if let selected = model.selectedOption {
                    selectedLayout {
                        AppIconImage(name: selected.previewImageName, size: 76)
                        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                            Text(selected.displayName)
                                .font(.title3.bold())
                            Text(String(localized: .settingsExplorePersonalizationCurrentIcon))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    ContentUnavailableView(
                        String(localized: .settingsExplorePersonalizationIconUnavailable),
                        systemImage: "app.dashed",
                    )
                }
            }
        }
    }

    private var selectedLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(alignment: .leading, spacing: stylesheet.spacing.medium))
        } else {
            AnyLayout(HStackLayout(spacing: stylesheet.spacing.medium))
        }
    }
}

#if DEBUG
    #Preview {
        FeatureAppIconPreview(model: .preview(activeAlternateIconName: "AppIconPride"))
            .padding()
            .whereBroadwayRoot()
    }
#endif
