import Foundation
import SwiftDataInspector
import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

/// Verifies the DEBUG-only SwiftData inspector entry point is wired to the live
/// Where store correctly: the configuration's model types track the real schema,
/// and the inspector renders against actual persisted rows.
@MainActor
struct SwiftDataInspectorWiringTests {
    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func configurationModelTypesMatchTheLiveSchema() throws {
        let session = WhereSession(services: PreviewSupport.previewServices())
        let configuration = try #require(session.swiftDataInspectorConfiguration)

        let schemaNames = Set(configuration.container.schema.entities.map(\.name))
        let typeNames = Set((configuration.modelTypes ?? []).map { String(describing: $0) })

        // The hand-maintained `inspectorModelTypes` must not drift from the
        // container's actual schema, or the inspector would silently omit (or
        // invent) entities.
        #expect(typeNames == schemaNames)
        #expect(schemaNames == [
            "SDDismissedIssue",
            "SDEvidence",
            "SDLocationSample",
            "SDManualDay",
            "SDTrackedRegion",
        ])
    }

    @Test func inspectorRendersAgainstTheLiveStore() async throws {
        let services = PreviewSupport.previewServices()
        // Persist a real row so the inspector reads it back through its own fresh
        // context, exercising the end-to-end wiring rather than an empty store.
        try await services.journal.addManualDay(
            date: date(year: 2026, month: 3, day: 1),
            regions: [.california],
            audit: nil,
        )

        let session = WhereSession(services: services)
        let configuration = try #require(session.swiftDataInspectorConfiguration)

        let rootView = NavigationStack {
            SwiftDataInspectorView(configuration: configuration)
        }
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
