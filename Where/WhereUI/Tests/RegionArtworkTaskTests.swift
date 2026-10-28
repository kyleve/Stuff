import RegionKit
import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct RegionArtworkTaskTests {
    @Test func reloadsForRegionAndCacheChangesAndClearsWhenCacheIsRemoved() throws {
        let model = RegionArtworkModel<Region, ObjectIdentifier>()
        let firstCache = RegionOutlinePathCache()
        let secondCache = RegionOutlinePathCache()
        var loads = 0

        func content(region: Region, cache: RegionOutlinePathCache?) -> some View {
            Color.clear
                .regionArtworkTask(id: region, model: model) { cache in
                    loads += 1
                    return ObjectIdentifier(cache)
                }
                .environment(\.regionOutlinePathCache, cache)
        }

        let host = UIHostingController(rootView: content(region: .canada, cache: firstCache))
        try show(host) { _ in
            try waitFor { model.artwork(for: .canada) == ObjectIdentifier(firstCache) }
            host.rootView = content(region: .newYork, cache: firstCache)
            try waitFor { model.artwork(for: .newYork) == ObjectIdentifier(firstCache) }
            #expect(model.artwork(for: .canada) == nil)
            host.rootView = content(region: .newYork, cache: secondCache)
            try waitFor { model.artwork(for: .newYork) == ObjectIdentifier(secondCache) }
            host.rootView = content(region: .newYork, cache: nil)
            try waitFor { model.artwork(for: .newYork) == nil }
            #expect(loads == 3)
        }
    }
}
