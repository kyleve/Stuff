import PeriscopeCore
import Testing

struct LogExportRequirementsTests {
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
