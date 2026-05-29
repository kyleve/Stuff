import SwiftUI
import WhereCore

/// The app's root: a Liquid Glass tab bar over the three top-level screens.
/// Owns the single `WhereModel`, builds the live controller on appear, and
/// hands the model down through the environment.
public struct RootView: View {
    @State private var model = WhereModel()

    public init() {}

    public var body: some View {
        TabView {
            Tab(Strings.tabPrimary, systemImage: "star.fill") {
                PrimaryView()
            }

            Tab(Strings.tabElsewhere, systemImage: "globe.americas.fill") {
                SecondaryView()
            }

            Tab(Strings.tabSettings, systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(model)
        .task { await model.start() }
    }
}

#if DEBUG
    #Preview {
        RootView()
    }
#endif
