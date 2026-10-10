import Foundation
import PeriscopeCore
import Testing

struct LogExportRequirementsTests {
    @Test(arguments: [false, true])
    func errorDefaultsUseIdentityInLiveAndPersistedExports(optionalIsNil: Bool) throws {
        let snapshot = LogError(capturing: NSError(
            domain: "private domain",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "private description"],
        ))
        let shadowed = LogExportTestLog.LogError(email: "private@example.test")
        let event = LogExportTestLog.ErrorDefaults(
            shadowed: .restricted(.errorDetails, shadowed),
            optionalShadowed: .restricted(.errorDetails, optionalIsNil ? nil : shadowed),
            qualified: .restricted(.errorDetails, snapshot),
            optionalQualified: .restricted(.errorDetails, optionalIsNil ? nil : snapshot),
            aliased: .restricted(.errorDetails, snapshot),
            optionalAliased: .restricted(.errorDetails, optionalIsNil ? nil : snapshot),
            denied: .restricted(.errorDetails, snapshot),
        )
        let raw = try JSONValue.encoding(event)
        let metadata = try JSONDecoder().decode(
            LogExportMetadata.self,
            from: JSONEncoder().encode(LogExportMetadata(payload: event.exportDescription.schema)),
        )
        let diagnostic = LogExportPolicy(mode: .diagnostic, enabledControls: [])
        let safeError: JSONValue = .object([
            "code": .int(42),
            "causes": .array([]),
            "omitted_causes": .array([]),
            "decoding": .null,
        ])
        let expected: JSONValue = .object([
            "qualified": safeError,
            "aliased": safeError,
            "optional_qualified": optionalIsNil ? .null : safeError,
            "optional_aliased": optionalIsNil ? .null : safeError,
        ])
        #expect(try event.exportedValue(using: diagnostic) == expected)
        #expect(try metadata.filtered(raw, using: diagnostic) == expected)

        let baseline = LogExportPolicy(mode: .baseline, enabledControls: [.personalData])
        #expect(try event.exportedValue(using: baseline) == .object([:]))
        #expect(try metadata.filtered(raw, using: baseline) == .object([:]))

        let granted = LogExportPolicy(mode: .diagnostic, enabledControls: [.personalData])
        let permitted = try event.exportedValue(using: granted)
        #expect(try metadata.filtered(raw, using: granted) == permitted)
        guard case let .object(fields) = permitted else {
            Issue.record("Expected an exported event object")
            return
        }
        #expect(fields["shadowed"] == .object(["email": .string(shadowed.email)]))
        #expect(fields["optional_shadowed"] == (optionalIsNil ? .null : fields["shadowed"]))
        #expect(fields["denied"] == nil)
    }

    @Test func parentAndChildRequireEveryControl() {
        let child = LogExportRequirements.baseline(requiring: [.location])
        let parent = LogExportRequirements.diagnostic(requiring: [.identifiers])
        #expect(child.constrained(by: parent) == .diagnostic(requiring: [.location, .identifiers]))
        #expect(parent.constrained(by: child) == child.constrained(by: parent))
    }

    @Test(arguments: [
        LogExportRequirements.baseline(requiring: []),
        .baseline(requiring: [.location]),
        .diagnostic(requiring: []),
        .diagnostic(requiring: [.customerDiagnostics]),
        .never,
    ])
    func neverExportCannotBeWeakened(_ requirements: LogExportRequirements) {
        #expect(requirements.constrained(by: .never) == .never)
        #expect(LogExportRequirements.never.constrained(by: requirements) == .never)
    }

    @Test func combiningRequirementsIsAssociative() {
        let first = LogExportRequirements.baseline(requiring: [.identifiers])
        let second = LogExportRequirements.diagnostic(requiring: [.location])
        let third = LogExportRequirements.baseline(requiring: [.customerDiagnostics])
        #expect(first.constrained(by: second).constrained(by: third)
            == first.constrained(by: second.constrained(by: third)))
    }

    @Test(arguments: [
        LogExportRequirements.baseline(requiring: []),
        .baseline(requiring: [.location]),
        .diagnostic(requiring: []),
        .diagnostic(requiring: [.customerDiagnostics]),
        .never,
    ], [
        LogExportRequirements.baseline(requiring: []),
        .baseline(requiring: [.identifiers]),
        .diagnostic(requiring: []),
        .diagnostic(requiring: [.customerDiagnostics]),
        .never,
    ])
    func combinedPermissionRequiresBothInputs(
        child: LogExportRequirements,
        parent: LogExportRequirements,
    ) {
        for mode: LogExportPolicy.Mode in [.baseline, .diagnostic] {
            for controls: Set<LogExportControl> in [
                [],
                [.location],
                [.location, .identifiers, .customerDiagnostics],
            ] {
                let policy = LogExportPolicy(mode: mode, enabledControls: controls)
                #expect(policy.allows(child.constrained(by: parent))
                    == (policy.allows(child) && policy.allows(parent)))
            }
        }
    }
}
