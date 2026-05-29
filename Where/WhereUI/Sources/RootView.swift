import SwiftUI
import WhereCore

/// The app's root: a Liquid Glass tab bar over the three top-level screens.
/// Owns the single `WhereModel`, builds the live controller on appear, and
/// hands the model down through the environment.
public struct RootView: View {
    @State private var model: WhereModel

    /// Inject the app-owned model that was built at launch (so CoreLocation is
    /// already wired up for background relaunch). The app uses this.
    public init(model: WhereModel) {
        _model = State(initialValue: model)
    }

    /// Convenience for previews and the hosted UI test, which don't need the
    /// launch-built model.
    public init() {
        _model = State(initialValue: WhereModel())
    }

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
