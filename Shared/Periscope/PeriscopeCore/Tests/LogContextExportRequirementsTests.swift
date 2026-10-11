import PeriscopeCore
import Testing

struct LogContextExportRequirementsTests {
    @Test(arguments: [
        LogContextExportRequirements.externalID,
        LogContextExportRequirements.sessionID,
        LogContextExportRequirements.spanID,
    ])
    func identitiesRequireDiagnosticIdentifiers(_ requirement: LogExportRequirements) {
        #expect(requirement == .diagnostic(requiring: [.identifiers]))
    }

    @Test func datesAndSessionDetailsRequirePersonalData() {
        #expect(LogContextExportRequirements.date == .diagnostic(requiring: [.personalData]))
        #expect(LogContextExportRequirements
            .sessionDetails == .diagnostic(requiring: [.personalData]))
    }

    @Test(arguments: [
        LogContextExportRequirements.tags,
        LogContextExportRequirements.scopes,
        LogContextExportRequirements.sessionAttributes,
        LogContextExportRequirements.attachmentMetadata,
    ])
    func unclassifiedContextRequiresEveryBuiltInGrant(_ requirement: LogExportRequirements) {
        let controls: Set<LogExportControl> = [.identifiers, .location, .userContent, .personalData]
        #expect(requirement == .diagnostic(requiring: controls))
        #expect(LogExportPolicy(mode: .baseline, enabledControls: controls)
            .allows(requirement) == false)
        #expect(LogExportPolicy(mode: .diagnostic, enabledControls: controls).allows(requirement))
        for missing in controls {
            var grants = controls.subtracting([missing])
            grants.insert(LogExportControl("com.example.unrelated"))
            #expect(LogExportPolicy(mode: .diagnostic, enabledControls: grants)
                .allows(requirement) == false)
        }
    }
}
