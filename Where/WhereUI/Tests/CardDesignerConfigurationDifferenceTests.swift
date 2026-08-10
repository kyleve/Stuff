#if DEBUG
    import Testing
    @testable import WhereUI

    struct CardDesignerConfigurationDifferenceTests {
        @Test func swiftAssignmentsContainOnlyEditedLeafValues() throws {
            var configuration = CardDesignerConfiguration.standard
            configuration.regular.cornerRadius = 31.25
            configuration.regular.sheen.spectralRim.travel = 1.2
            configuration.shared.darkSecurityPrint.blendMode = .softLight

            let assignments = try CardDesignerConfigurationDifference.swiftAssignments(
                for: configuration,
            )

            #expect(
                assignments == [
                    "configuration.regular.cornerRadius = 31.25",
                    "configuration.regular.sheen.spectralRim.travel = 1.2",
                    "configuration.shared.darkSecurityPrint.blendMode = .softLight",
                ],
            )
        }

        @Test func standardConfigurationHasNoSwiftAssignments() throws {
            let assignments = try CardDesignerConfigurationDifference.swiftAssignments(
                for: .standard,
            )

            #expect(assignments.isEmpty)
        }
    }
#endif
