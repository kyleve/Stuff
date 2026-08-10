#if DEBUG
    import Foundation
    import Testing
    @testable import WhereUI

    struct CardDesignerJSONExporterTests {
        @Test func diffRetainsSchemaAndContainsOnlyEditedLeafValues() throws {
            var configuration = CardDesignerConfiguration.standard
            configuration.regular.cornerRadius = 31.25
            configuration.shared.darkSecurityPrint.whiteMix = 0.4

            let data = try CardDesignerJSONExporter.data(
                for: configuration,
                diffOnly: true,
            )
            let object = try #require(
                JSONSerialization.jsonObject(with: data) as? [String: Any],
            )
            let regular = try #require(object["regular"] as? [String: Any])
            let shared = try #require(object["shared"] as? [String: Any])
            let dark = try #require(shared["darkSecurityPrint"] as? [String: Any])

            #expect(object["schemaVersion"] as? Int == 5)
            #expect(regular["cornerRadius"] as? Double == 31.25)
            #expect(regular["padding"] == nil)
            #expect(object["compact"] == nil)
            #expect(dark["whiteMix"] as? Double == 0.4)
            #expect(dark["blendMode"] == nil)
        }

        @Test func fullExportRoundTripsTheConfiguration() throws {
            var configuration = CardDesignerConfiguration.standard
            configuration.compact.padding = 19

            let data = try CardDesignerJSONExporter.data(
                for: configuration,
                diffOnly: false,
            )

            #expect(try JSONDecoder()
                .decode(CardDesignerConfiguration.self, from: data) == configuration)
        }
    }
#endif
