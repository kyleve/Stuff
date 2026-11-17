import RegionKit
@_spi(Capture) import SnapshotKit
import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct RegionArtworkTaskTests {
    @Test(arguments: [false, true])
    func nestedRootsReuseInjectedOrRootOwnedCache(injectCache: Bool) throws {
        let injected = injectCache ? RegionOutlinePathCache() : nil
        var rootCaches: [RegionOutlinePathCache] = []

        for _ in 0 ..< 2 {
            let outer = RegionArtworkModel<Region, ObjectIdentifier>()
            let inner = RegionArtworkModel<Region, ObjectIdentifier>()
            var received: RegionOutlinePathCache?
            let host = UIHostingController(rootView: VStack {
                Color.clear.regionArtworkTask(id: Region.canada, model: outer) {
                    received = $0
                    return ObjectIdentifier($0)
                }
                Color.clear.regionArtworkTask(id: Region.canada, model: inner) {
                    ObjectIdentifier($0)
                }
                .whereBroadwayRoot(theme: .alternate)
            }
            .whereBroadwayRoot()
            .environment(\.regionOutlinePathCache, injected))

            try show(host) { _ in
                try waitFor {
                    outer.artwork(for: .canada) != nil && inner.artwork(for: .canada) != nil
                }
                let root = try #require(outer.artwork(for: .canada))
                #expect(inner.artwork(for: .canada) == root)
                if let injected {
                    #expect(root == ObjectIdentifier(injected))
                }
                try rootCaches.append(#require(received))
            }
        }

        if injectCache {
            #expect(rootCaches[0] === rootCaches[1])
        } else {
            #expect(rootCaches[0] !== rootCaches[1])
        }
    }

    @Test func snapshotHelpersSharePathsWithIndependentArtworkPublication() async throws {
        var models: [RegionArtworkModel<Region, ObjectIdentifier>] = []
        let content: @MainActor @Sendable () -> AnyView = {
            let model = RegionArtworkModel<Region, ObjectIdentifier>()
            models.append(model)
            return AnyView(Color.clear.regionArtworkTask(id: Region.canada, model: model) {
                ObjectIdentifier($0)
            })
        }

        let cases = [
            whereSnapshot(name: "Single", configurations: .phoneLightDark, content: content),
            whereThemeSnapshot(
                name: "Themes",
                configurations: .componentLightDark,
                content: content,
            ),
        ]
        let expected = ObjectIdentifier(PreviewSupport.snapshotArtworkCache)
        for snapshotCase in cases {
            let modelOffset = models.count
            let subjects: [AnyView] = switch snapshotCase.capture {
                case let .single(makeContent): [makeContent()]
                case let .cutsheet(collection): collection.panels.map(\.content)
            }
            for (index, subject) in subjects.enumerated() {
                let model = models[modelOffset + index]
                let host = UIHostingController(rootView: subject)
                try show(host) { _ in
                    try waitFor { model.artwork(for: .canada) == expected }
                }
            }
        }

        #expect(models.count == 1 + WhereTheme.allCases.count)
        for model in models {
            #expect(model.artwork(for: .canada) == expected)
        }
        let first = try #require(models.first)
        await first.load(for: .canada) { nil }
        #expect(first.artwork(for: .canada) == nil)
        for model in models.dropFirst() {
            #expect(model.artwork(for: .canada) == expected)
        }
    }

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
