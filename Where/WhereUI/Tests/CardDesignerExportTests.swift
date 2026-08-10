#if DEBUG
    import Testing
    @testable import WhereUI

    struct CardDesignerExportTests {
        @Test func swiftExportIsDeterministicAndContainsBothAppearances() {
            let configuration = CardDesignerConfiguration.standard

            let first = CardDesignerSwiftExporter.source(for: configuration)
            let second = CardDesignerSwiftExporter.source(for: configuration)

            #expect(first == second)
            #expect(first.contains("let regularCardStyle"))
            #expect(first.contains("let compactCardStyle"))
            #expect(first.contains("let lightCardStyles"))
            #expect(first.contains("let darkCardStyles"))
            #expect(first.contains("backgroundBlendMode: .luminosity"))
            #expect(first.contains("spectralRim: .init("))
            #expect(first.contains("lineWidth: 2.75"))
            #expect(first.contains("blurRadius: 4"))
        }

        @Test func swiftExportReflectsEditedValues() {
            var configuration = CardDesignerConfiguration.standard
            configuration.regular.cornerRadius = 31.25
            configuration.regular.sheen.spectralRim.lineWidth = 3.25
            configuration.shared.darkSecurityPrint.whiteMix = 0.4

            let source = CardDesignerSwiftExporter.source(for: configuration)

            #expect(source.contains("cornerRadius: 31.25"))
            #expect(source.contains("lineWidth: 3.25"))
            #expect(source.contains("whiteMix: 0.4"))
        }

        @Test func swiftDiffContainsOnlyEditedLeafValues() {
            var configuration = CardDesignerConfiguration.standard
            configuration.regular.cornerRadius = 31.25
            configuration.shared.darkSecurityPrint.blendMode = .softLight

            let source = CardDesignerSwiftExporter.source(
                for: configuration,
                diffOnly: true,
            )

            #expect(source.contains("var configuration = CardDesignerConfiguration.standard"))
            #expect(source.contains("configuration.regular.cornerRadius = 31.25"))
            #expect(
                source.contains("configuration.shared.darkSecurityPrint.blendMode = .softLight"),
            )
            #expect(source.contains("configuration.regular.padding") == false)
            #expect(source.contains("configuration.compact") == false)
        }

        @Test func unchangedSwiftDiffExplainsThatThereAreNoChanges() {
            let source = CardDesignerSwiftExporter.source(
                for: .standard,
                diffOnly: true,
            )

            #expect(source.contains("No card appearance values differ from standard."))
            #expect(source.contains("configuration.regular") == false)
        }
    }
#endif
