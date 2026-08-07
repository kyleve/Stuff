#if DEBUG
    import Foundation

    enum CardDesignerJSONExporter {
        static func data(
            for configuration: CardDesignerConfiguration,
            diffOnly: Bool,
        ) throws -> Data {
            if diffOnly {
                return try JSONSerialization.data(
                    withJSONObject: CardDesignerConfigurationDifference.jsonObject(
                        for: configuration,
                    ),
                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes],
                )
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(configuration)
        }

        static func text(
            for configuration: CardDesignerConfiguration,
            diffOnly: Bool,
        ) -> String {
            do {
                return try String(
                    decoding: data(for: configuration, diffOnly: diffOnly),
                    as: UTF8.self,
                )
            } catch {
                assertionFailure("Card designer JSON export failed: \(error)")
                return "{}"
            }
        }
    }
#endif
