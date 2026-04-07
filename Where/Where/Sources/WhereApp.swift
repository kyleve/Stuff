import SwiftUI
import WhereData
import WhereUI

@main
struct WhereApp: App {
    @State private var viewModel = RootViewModel(provider: YearProgressController())

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel)
        }
    }
}
