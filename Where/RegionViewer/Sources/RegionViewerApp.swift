import SwiftUI
import WhereUI

/// Thin standalone host for `RegionMapView` — a Mac Catalyst (and iOS)
/// developer tool for inspecting the bundled region geometry on a real map,
/// outside the full Where app and its onboarding/session.
///
/// All behavior lives in `WhereUI` / `WhereCore`; this target is just the
/// `@main` shell. There is no `WhereSession`, no SwiftData store, and no App
/// Group — `RegionMapView` reads geometry straight from
/// `RegionGeometryCatalog`, which only needs the bundled GeoJSON.
@main
struct RegionViewerApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                RegionMapView()
            }
        }
    }
}
