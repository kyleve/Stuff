import InstallerKit
@_spi(Testing) @testable import InstallerKitUI
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class UpdateBrowserNavigationFixture {
    enum Page: Equatable {
        case hidden
        case channels
        case destination(UpdateBrowserView.Route)
    }

    var path: [UpdateBrowserView.Route] = []
    var visiblePage = Page.hidden
}

/// Hosts the browser's root and destinations with a controllable path and appearance signals.
struct UpdateBrowserTestHost: View {
    let model: UpdateModel
    @Bindable var navigation: UpdateBrowserNavigationFixture

    var body: some View {
        NavigationStack(path: $navigation.path) {
            UpdateChannelsView(model: model)
                .onAppear { navigation.visiblePage = .channels }
                .navigationDestination(for: UpdateBrowserView.Route.self) { route in
                    route.destination(model: model, branding: InstallerPreview.branding)
                        .onAppear { navigation.visiblePage = .destination(route) }
                }
        }
        .installerBroadwayRoot()
    }
}

@MainActor
func installerNavigationController(in controller: UIViewController) -> UINavigationController? {
    if let navigation = controller as? UINavigationController { return navigation }
    return controller.children.lazy.compactMap { installerNavigationController(in: $0) }.first
}
