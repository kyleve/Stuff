import InstallerKit
import SwiftUI
#if DEBUG
    import PeriscopeTools
#endif

/// A complete app world, or a sibling world that cannot inherit app integrations.
/// The app derives its session from its model; isolated hosts must choose a session explicitly.
@MainActor
enum WhereEnvironment {
    case app(App)
    case isolated(model: WhereModel, session: WhereSession?)

    struct App {
        let model: WhereModel
        let updates: UpdateModel?
        #if DEBUG
            let developer: Developer
        #endif
    }

    #if DEBUG
        struct Developer {
            let inspector: PeriscopeInspector?
            let launchController: WhereDeveloperLaunchController?
            let cardDesigner: CardDesignerModel?
        }
    #endif

    var app: App? {
        switch self {
            case let .app(app): app
            case .isolated: nil
        }
    }

    var model: WhereModel {
        switch self {
            case let .app(app): app.model
            case let .isolated(model, _): model
        }
    }

    var session: WhereSession? {
        switch self {
            case let .app(app): app.model.session
            case let .isolated(_, session): session
        }
    }

    var isInDemoMode: Bool {
        switch self {
            case let .app(app): app.model.isInDemoMode
            case .isolated: true
        }
    }
}

extension View {
    /// Replaces the world and all scope-sensitive app dependencies, including absent values.
    /// Identity such as the installed app's primary icon can still come from the host.
    func whereEnvironment(_ environment: WhereEnvironment) -> some View {
        modifier(WhereEnvironmentModifier(environment: environment))
    }
}

private struct WhereEnvironmentModifier: ViewModifier {
    let environment: WhereEnvironment

    func body(content: Content) -> some View {
        content
            .environment(environment.model)
            .environment(environment.session)
            .environment(environment.app?.updates)
            .environment(\.isInDemoMode, environment.isInDemoMode)
        #if DEBUG
            .environment(\.periscopeInspector, environment.app?.developer.inspector)
            .environment(environment.app?.developer.launchController)
            .environment(\.cardDesignerModel, environment.app?.developer.cardDesigner)
            .environment(
                \.cardDesignerConfiguration,
                environment.app?.developer.cardDesigner.flatMap {
                    $0.appliesToApp ? $0.configuration : nil
                },
            )
        #endif
            .whereBroadwayRoot(WherePresentationContext(
                theme: environment.model.theme,
                regionStyles: environment.session?.regionStyles ?? .default,
            ))
    }
}
