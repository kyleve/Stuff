#if DEBUG
    import SwiftUI
    import Testing
    import UIKit
    @testable import WhereUI

    @MainActor
    struct CardDesignerStudioViewTests {
        @Test func hostsWithStandardConfiguration() {
            let model = CardDesignerModel(configuration: .standard)
            let controller = UIHostingController(
                rootView: NavigationStack {
                    CardDesignerStudioView(model: model)
                },
            )

            #expect(controller.view != nil)
            #expect(model.configuration == .standard)
        }
    }
#endif
