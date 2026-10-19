import InstallerKit
@_spi(Testing) import InstallerKitUI
import Observation
import SwiftUI
import TestHostSupport
import WhereCore
@testable import WhereUI

@MainActor
func findTabController(in controller: UIViewController) -> UITabBarController? {
    if let tabs = controller as? UITabBarController { return tabs }
    return controller.children.lazy.compactMap { findTabController(in: $0) }.first
}

@MainActor
@Observable
final class UpdateSceneFixture {
    var phase = ScenePhase.background
    var renderedPhase: ScenePhase?
    var now = InstallerPreview.date
}

struct UpdateSceneHost: View {
    let fixture: UpdateSceneFixture
    let session: WhereSession
    let updates: UpdateModel
    private let model = PreviewSupport.loadedModel()

    var body: some View {
        MainTabs(
            session: session,
            initialDetails: PreviewSupport.sampleYearReportDetails(),
            selectedYear: PreviewSupport.year,
        )
        .environment(session)
        .environment(model)
        .environment(updates)
        .environment(\.scenePhase, fixture.phase)
        .whereBroadwayRoot()
        .onChange(of: fixture.phase, initial: true) { _, phase in
            fixture.renderedPhase = phase
        }
    }
}

@MainActor
func waitForUpdateScene(_ predicate: () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(10))
    while !predicate() {
        guard clock.now < deadline
        else { throw TestHostError("Timed out waiting for the update scene") }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
final class UpdateSceneClient: UpdateFetching {
    let catalog: UpdateCatalog
    private(set) var fetchCount = 0

    init(_ catalog: UpdateCatalog) {
        self.catalog = catalog
    }

    func fetch(from _: URL) async throws -> UpdateCatalog {
        fetchCount += 1
        return catalog
    }
}
