#if DEBUG
    import Foundation
    import SwiftUI
    import Testing
    @testable import WhereUI

    struct CardDesignerConfigurationTests {
        @Test func standardResolvesToTheProductionLightStyle() {
            let resolved = CardDesignerConfiguration.standard.resolve(
                over: .standard,
                colorScheme: .light,
            )
            #expect(resolved == .standard)
        }

        @Test func standardResolvesToTheProductionDarkStyle() {
            var expected = WhereStylesheet.CardStyles.standard
            expected.securityPrint = .dark
            let resolved = CardDesignerConfiguration.standard.resolve(
                over: .standard,
                colorScheme: .dark,
            )
            #expect(resolved == expected)
        }

        @Test func configurationRoundTripsThroughVersionedJSON() throws {
            var configuration = CardDesignerConfiguration.standard
            configuration.regular.cornerRadius = 33
            configuration.compact.regionNameTypography.size = .fixed(19)
            configuration.shared.darkSecurityPrint.blendMode = .softLight

            let data = try JSONEncoder().encode(configuration)
            let decoded = try JSONDecoder().decode(CardDesignerConfiguration.self, from: data)

            #expect(decoded == configuration)
            #expect(decoded.schemaVersion == CardDesignerConfiguration.currentSchemaVersion)
        }

        @Test(arguments: CardDesignerBlendMode.allCases)
        func everyBlendModeRoundTrips(_ blendMode: CardDesignerBlendMode) {
            #expect(CardDesignerBlendMode(blendMode.style) == blendMode)
        }

        @Test func variantSubscriptReadsAndWritesIndependently() {
            var configuration = CardDesignerConfiguration.standard
            let compactRadius = configuration[.compact].cornerRadius
            configuration[.regular].cornerRadius = 41

            #expect(configuration[.regular].cornerRadius == 41)
            #expect(configuration[.compact].cornerRadius == compactRadius)
        }
    }
#endif
