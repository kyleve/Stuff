import SwiftDataInspector
import Testing
@testable import WhereUI

/// Verifies the DEBUG-only SwiftData inspector entry point is wired to the live
/// Where store correctly: the configuration's model types track the real schema.
/// (Rendering against a seeded store is covered by the inspector snapshot in
/// `WhereUISnapshotTests`.)
@MainActor
struct SwiftDataInspectorWiringTests {
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
}
