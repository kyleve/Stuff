import BroadwayUI
import SwiftUI

/// A developer browser for every registered state and navigation relationship in an app.
public struct FlyoverView<ScreenID: Hashable>: View {
    private let catalog: FlyoverCatalog<ScreenID>
    @State private var model: FlyoverModel<ScreenID>

    public init(catalog: FlyoverCatalog<ScreenID>) {
        self.catalog = catalog
        _model = State(initialValue: FlyoverModel(catalog: catalog))
    }

    init(catalog: FlyoverCatalog<ScreenID>, model: FlyoverModel<ScreenID>) {
        self.catalog = catalog
        _model = State(initialValue: model)
    }

    public var body: some View {
        FlyoverRootView(catalog: catalog, model: model)
            .broadwayRoot()
    }
}

#if DEBUG
    @MainActor enum FlyoverPreview {
        static let catalog: FlyoverCatalog<String> = {
            let screens = ["Inbox", "Message"].map { name in
                FlyoverScreen(id: name, title: name, variants: [
                    FlyoverVariant(id: FlyoverVariantID("populated"), title: "Populated") {
                        Text(name)
                    },
                    FlyoverVariant(id: FlyoverVariantID("empty"), title: "Empty") {
                        Text("No messages")
                    },
                ])
            }
            return FlyoverCatalog(
                groups: [FlyoverGroup(
                    id: FlyoverGroupID("mail"),
                    title: "Mail",
                    root: "Inbox",
                    screens: screens,
                )],
                transitions: [FlyoverTransition(from: "Inbox", to: "Message", kind: .push)],
            )
        }()
    }

    #Preview { FlyoverView(catalog: FlyoverPreview.catalog) }
#endif
