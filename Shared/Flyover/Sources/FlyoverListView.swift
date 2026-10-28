import SwiftUI

/// A linear alternative to the spatial Flyover canvas.
struct FlyoverListView<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    let model: FlyoverModel<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: stylesheet.list.groupSpacing) {
                ForEach(catalog.groups, id: \.id) { group in
                    Section {
                        ForEach(group.screens, id: \.id) { screen in
                            FlyoverScreenFrame(
                                screen: screen,
                                catalog: catalog,
                                model: model,
                            )
                            .frame(maxWidth: .infinity)
                        }
                    } header: {
                        Text(group.title)
                            .font(stylesheet.list.groupTitleFont)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(stylesheet.list.contentPadding)
        }
    }
}
