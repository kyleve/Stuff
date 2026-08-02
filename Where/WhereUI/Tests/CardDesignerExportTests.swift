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
        }

        @Test func swiftExportReflectsEditedValues() {
            var configuration = CardDesignerConfiguration.standard
            configuration.regular.cornerRadius = 31.25
            configuration.shared.darkSecurityPrint.whiteMix = 0.4

            let source = CardDesignerSwiftExporter.source(for: configuration)

            #expect(source.contains("cornerRadius: 31.25"))
            #expect(source.contains("whiteMix: 0.4"))
        }
    }
#endif
