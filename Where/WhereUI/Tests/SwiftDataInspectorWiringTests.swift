import SwiftDataInspector
import Testing
@testable import WhereUI

/// Verifies the DEBUG-only SwiftData inspector entry point is wired to the live
/// Where store correctly: the configuration's model types track the real schema.
/// (How the inspector *renders* is covered by SwiftDataInspector's own image
/// snapshots, over that module's fixture schema rather than Where's store — so
/// this is the only test tying the inspector to the real one.)
@MainActor
struct SwiftDataInspectorWiringTests {
    @Test func configurationModelTypesMatchTheLiveSchema() throws {
        let session = WhereSession(
            services: PreviewSupport.previewServices(),
            preferences: PreviewSupport.previewPreferences(),
        )
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
            "SDRecordingDevice",
            "SDRecordingPolicyChange",
            "SDTrackedRegion",
        ])
    }
}
