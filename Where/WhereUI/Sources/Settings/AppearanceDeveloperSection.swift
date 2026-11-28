#if DEBUG
    import SFSafeSymbols
    import SwiftUI

    struct AppearanceDeveloperSection: View {
        @Environment(\.cardDesignerModel) private var cardDesignerModel

        var body: some View {
            if let cardDesignerModel {
                Section {
                    NavigationLink {
                        CardDesignerStudioView(model: cardDesignerModel)
                    } label: {
                        Label(
                            String(localized: .cardDesignerTitle),
                            systemSymbol: .paintpalette,
                        )
                    }
                    .settingsRow(AppearanceSettingsView.Item.cardDesigner)

                    NavigationLink {
                        RankingAnimationLabView()
                    } label: {
                        Label(
                            String(localized: .rankingAnimationTitle),
                            systemSymbol: .arrowUpArrowDown,
                        )
                    }
                    .settingsRow(AppearanceSettingsView.Item.rankingAnimation)
                } header: {
                    Text(String(localized: .cardDesignerSettingsHeader))
                } footer: {
                    Text(String(localized: .cardDesignerSettingsFooter))
                }
            }
        }
    }

    #Preview { NavigationStack { AppearanceSettingsView.snapshotPreviews }.whereBroadwayRoot() }
#endif
