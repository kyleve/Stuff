import PortholeCore
@testable import PortholeUI
import Testing

@MainActor
struct PortholeCoverageEntryPresentationTests {
    @Test(arguments: [
        PortholeCoverageState.inactive,
        .inspectableSource,
        .unsupported("Callback unsupported"),
        .sourceOnly("Extension constraint"),
        .excluded("Credential machinery"),
    ])
    func plannedCallableNeverCreatesACallForm(state: PortholeCoverageState) {
        let original = PortholeCoverageSnapshotServices.entries[0]
        let entry = PortholeCoverageEntry(
            module: original.module,
            declaration: original.declaration,
            state: state,
            installedCapabilityID: original.installedCapabilityID,
        )
        #expect(entry.callableCapability(in: [PortholeCoverageSnapshotServices.callable]) == nil)
        #expect(entry.plannedSupportTitle == "Planned callable")
    }

    @Test func actualCallableRequiresItsRegisteredDescriptor() {
        let entry = PortholeCoverageSnapshotServices.entries[0]
        #expect(entry.callableCapability(in: [PortholeCoverageSnapshotServices.callable]) != nil)
        #expect(entry.callableCapability(in: []) == nil)
        let missing = PortholeCoverageEntry(
            module: entry.module,
            declaration: entry.declaration,
            state: .callable,
            installedCapabilityID: nil,
        )
        #expect(missing.callableCapability(in: [PortholeCoverageSnapshotServices.callable]) == nil)
    }

    @Test func inactiveRetainsConditionsAndFinalPlannerReason() {
        let original = PortholeCoverageSnapshotServices.entries[2]
        let entry = PortholeCoverageEntry(
            module: original.module,
            declaration: original.declaration,
            state: .inactive,
            installedCapabilityID: nil,
        )
        #expect(entry.statusTitle == "Inactive in this build")
        #expect(PortholeCoverageSnapshotServices.entries[3].declaration.conditions == ["DEBUG"])
        #expect(entry
            .plannedSupportReason == "Unbound generic parameter T requires a concrete type.")
        #expect(entry.declaration.sourceSHA256 == PortholeCoverageSnapshotServices.sourceFile
            .sha256)
        guard let evidence = entry.sourceEvidence(in: PortholeCoverageSnapshotServices.scope),
              case let .source(reference) = evidence
        else { Issue.record("Missing verified source link"); return }
        #expect(reference.scope == PortholeCoverageSnapshotServices.scope)
        #expect(reference.line == 3)
        #expect(reference.sha256 == PortholeCoverageSnapshotServices.sourceFile.sha256)
    }
}
