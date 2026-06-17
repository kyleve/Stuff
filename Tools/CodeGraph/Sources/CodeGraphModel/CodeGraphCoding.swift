import Foundation

/// Shared JSON coding configuration so the extractor (writer) and the viewer
/// (reader) always agree on the `graph.json` format: ISO-8601 dates and a
/// stable key order that diffs cleanly in source control.
public enum CodeGraphCoding {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
