import Foundation
import PeriscopeCore
import Testing

struct LogExportPolicyTests {
    @Test func diagnosticModeDoesNotGrantAnyControls() {
        let policy = LogExportPolicy(mode: .diagnostic, enabledControls: [])
        #expect(policy.allows(.diagnostic(requiring: [])))
        #expect(policy.allows(.diagnostic(requiring: [.location])) == false)
        #expect(policy[.customerDiagnostics] == false)
    }

    @Test func controlsCannotEnableDiagnosticMode() {
        let policy = LogExportPolicy(mode: .baseline, enabledControls: [.location])
        #expect(policy.allows(.baseline(requiring: [.location])))
        #expect(policy.allows(.diagnostic(requiring: [.location])) == false)
    }

    @Test func allRequiredControlsMustBeEnabled() {
        var policy = LogExportPolicy(mode: .diagnostic, enabledControls: [.location])
        let requirements = LogExportRequirements.diagnostic(requiring: [
            .location,
            .customerDiagnostics,
        ])
        #expect(policy.allows(requirements) == false)
        policy[.customerDiagnostics] = true
        #expect(policy.allows(requirements))
        policy[.location] = false
        #expect(policy.allows(requirements) == false)
        #expect(policy[.customerDiagnostics])
    }

    @Test func personalDataIsNotAWildcard() {
        let policy = LogExportPolicy(mode: .diagnostic, enabledControls: [.personalData])
        #expect(policy.allows(.diagnostic(requiring: [.personalData])))
        #expect(policy.allows(.diagnostic(requiring: [.identifiers])) == false)
        #expect(policy.allows(.diagnostic(requiring: [.location])) == false)
        #expect(policy.allows(.diagnostic(requiring: [.userContent])) == false)
        #expect(policy.allows(.diagnostic(requiring: [.customerDiagnostics])) == false)
    }

    @Test func combinedSwitchPreservesUnrelatedControls() {
        var policy = LogExportPolicy(mode: .diagnostic, enabledControls: [.customerDiagnostics])
        let personalControls: Set<LogExportControl> = [
            .personalData,
            .identifiers,
            .location,
            .userContent,
        ]
        policy.setEnabled(true, for: personalControls)
        #expect(personalControls.isSubset(of: policy.enabledControls))
        #expect(policy[.customerDiagnostics])
        #expect(policy[.futureControl] == false)
        policy.setEnabled(false, for: personalControls)
        #expect(policy.enabledControls == [.customerDiagnostics])
    }

    @Test func neverExportRemainsDeniedWithAllNamedControlsEnabled() {
        let policy = LogExportPolicy(
            mode: .diagnostic,
            enabledControls: [
                .personalData,
                .identifiers,
                .location,
                .userContent,
                .customerDiagnostics,
            ],
        )
        #expect(policy.allows(.never) == false)
    }

    @Test func persistedPolicyPreservesExplicitCustomGrants() throws {
        let policy = LogExportPolicy(
            mode: .diagnostic,
            enabledControls: [.customerDiagnostics, .location],
        )
        let data = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(LogExportPolicy.self, from: data)
        #expect(decoded == policy)
        #expect(decoded[.futureControl] == false)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case let .object(fields) = json else {
            Issue.record("Expected a policy object")
            return
        }
        #expect(fields["mode"] == .string("diagnostic"))
        #expect(fields["enabled_controls"] != nil)
        #expect(fields["enabledControls"] == nil)
    }

    @Test func incompletePolicyCannotSilentlyGrantAccess() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                LogExportPolicy.self,
                from: Data("{\"mode\":\"diagnostic\"}".utf8),
            )
        }
    }
}
