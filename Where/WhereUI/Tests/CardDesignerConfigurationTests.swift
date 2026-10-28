#if DEBUG
    import BroadwayCore
    import Foundation
    import SwiftUI
    import Testing
    import WhereCore
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
            configuration.compact.regionNameTypography.sizeMode = .fixed
            configuration.compact.regionNameTypography.fixedSize = 19
            configuration.shared.darkSecurityPrint.blendMode = .softLight

            let data = try JSONEncoder().encode(configuration)
            let decoded = try JSONDecoder().decode(CardDesignerConfiguration.self, from: data)

            #expect(decoded == configuration)
            #expect(decoded.schemaVersion == CardDesignerConfiguration.currentSchemaVersion)
        }

        @MainActor
        @Test func savedDraftCannotRestoreReflectionsInFlat() throws {
            var themes = BThemes()
            themes[WhereTheme.self] = .alternate
            let context = BContext(traits: .system, themes: themes)
            let base = try context.stylesheets.get(WhereStylesheet.self).card
            var draft = CardDesignerConfiguration.standard
            draft.regular.cornerRadius = 33
            let resolved = draft.resolve(over: base, colorScheme: .light)
            #expect(resolved.regular.cornerRadius == 33)
            #expect(resolved.regular.surface == base.regular.surface)
            #expect(resolved.compact.surface == base.compact.surface)
            #expect(resolved.regular.contentTint == base.regular.contentTint)
            #expect(resolved.compact.contentTint == base.compact.contentTint)
            #expect(resolved.constellation.haloOpacity == 0)
            #expect(resolved.securityPrint == base.securityPrint)
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
