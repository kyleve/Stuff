import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct WhereEnvironmentTests {
    @Test func appProvidesOneConsistentWorldAndItsIntegrations() async throws {
        let support = try await WhereEnvironmentTestSupport()
        defer { support.cleanup() }
        let session = try #require(support.model.session)
        let appearance = RegionAppearance(color: .pink, emoji: "🎸", symbolName: .starFill)
        try await session.services.setPrimaryRegions([
            .init(region: .california, appearance: appearance, order: 0),
        ])
        await session.seedRegionStyles()
        support.model.previewTheme(.alternate)
        let reads = WhereEnvironmentTestSupport.Reads()
        let host = UIHostingController(rootView: WhereEnvironmentTestSupport.Probe(reads: reads)
            .whereEnvironment(support.environment))

        try show(host) { _ in
            try waitFor { reads.latest?.theme == .alternate }
            let values = try #require(reads.latest)
            #expect(values.model == ObjectIdentifier(support.model))
            #expect(values.session == ObjectIdentifier(session))
            #expect(values.updates == ObjectIdentifier(support.updates))
            #expect(values.isInDemoMode == false)
            #expect(values.regionStyles == session.regionStyles)
            #expect(values.regionStyles != .default)
            #expect(values.cache != nil)
            #expect(values.inspector == ObjectIdentifier(support.inspector))
            #expect(values.launchController == ObjectIdentifier(support.launchController))
            #expect(values.cardDesigner == ObjectIdentifier(support.cardDesigner))
            #expect(values.cardConfiguration == support.cardDesigner.configuration)
        }
    }

    @Test(arguments: [false, true])
    func isolatedWorldReplacesTheParentAndClearsItsIntegrations(withSession: Bool) async throws {
        let parent = try await WhereEnvironmentTestSupport()
        defer { parent.cleanup() }
        parent.model.previewTheme(.alternate)
        let child = WhereEnvironmentTestSupport.makeModel()
        let session = withSession ? child.session : nil
        let reads = WhereEnvironmentTestSupport.Reads()
        let host = UIHostingController(rootView: WhereEnvironmentTestSupport.Probe(reads: reads)
            .whereEnvironment(.isolated(model: child, session: session))
            .whereEnvironment(parent.environment))

        try show(host) { _ in
            try waitFor { reads.latest?.model == ObjectIdentifier(child) }
            let values = try #require(reads.latest)
            #expect(values.session == session.map(ObjectIdentifier.init))
            #expect(values.isInDemoMode)
            #expect(child.isInDemoMode == false)
            #expect(values.theme == .standard)
            #expect(values.regionStyles == session?.regionStyles ?? .default)
            #expect(values.cache != nil)
            #expect(values.updates == nil)
            #expect(values.inspector == nil)
            #expect(values.launchController == nil)
            #expect(values.cardDesigner == nil)
            #expect(values.cardConfiguration == nil)
            #expect(parent.model.session != nil)
            #expect(parent.model.theme == .alternate)
        }
    }

    @Test func mountedAppTracksThemeDemoSessionReplacementAndLogout() async throws {
        let model = WhereEnvironmentTestSupport.makeModel()
        let initialSession = try #require(model.session)
        let reads = WhereEnvironmentTestSupport.Reads()
        let host = UIHostingController(rootView: WhereEnvironmentTestSupport.Probe(reads: reads)
            .whereEnvironment(.app(.init(
                model: model,
                updates: nil,
                developer: .init(inspector: nil, launchController: nil, cardDesigner: nil),
            ))))

        try await show(host) { _ in
            try waitFor { reads.latest?.session == ObjectIdentifier(initialSession) }
            let cache = reads.latest?.cache
            model.previewTheme(.alternate)
            try waitFor { reads.latest?.theme == .alternate }
            #expect(reads.latest?.cache == cache)

            try await model.activateDemo(model.makeDemoScope())
            try waitFor { reads.latest?.isInDemoMode == true && reads.latest?.session == nil }
            let scope = try #require(model.activeScope)
            let demoSession = model.startSession(scope: scope)
            try waitFor { reads.latest?.session == ObjectIdentifier(demoSession) }
            #expect(reads.latest?.theme == model.theme)

            await model.deactivateDemo()
            try waitFor { reads.latest?.isInDemoMode == false && reads.latest?.session == nil }
            #expect(reads.latest?.cache == cache)
        }
    }
}
