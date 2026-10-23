import Foundation
import WhereCore

/// A recorded GPS window, separate from the test's independently reviewed expectations.
/// Samples and dates use their ordinary Codable shape. Coordinate
/// provenance describes the exported data, never the private input path or origin.
struct RecordedFlightFixture: Codable, Equatable {
    enum Coordinates: String, Codable {
        case rotated, original
    }

    enum Name: String, CaseIterable {
        case sparse = "sparse-flight"
        case legacySparse = "legacy-sparse-flight"
        case legacyMixed = "legacy-mixed-flight"
        case interruptedCruise = "interrupted-cruise-flight"
        case resumedCruise = "resumed-cruise-flight"
    }

    enum LoadError: Error {
        case missingResource(Name)
    }

    let coordinates: Coordinates
    let now: Date
    let samples: [LocationSample]

    /// Resolve inside the test bundle so CI's build-product handoff needs no source files.
    static func load(_ name: Name) throws -> Self {
        guard let url = Bundle(for: BundleAnchor.self).url(
            forResource: name.rawValue,
            withExtension: "json",
            subdirectory: "Flights",
        ) else { throw LoadError.missingResource(name) }
        return try read(from: url)
    }

    static func read(from url: URL) throws -> Self {
        try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN",
        )
        return try decoder.decode(Self.self, from: data)
    }

    func jsonData() throws -> Data {
        // Default Date coding uses the 2001 reference epoch. Converting to Unix seconds
        // can discard a sub-microsecond bit before JSON even sees the Double.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // Invalid sensor values are evidence too. Retain them without producing invalid JSON.
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN",
        )
        return try encoder.encode(self)
    }

    private final class BundleAnchor {}
}
