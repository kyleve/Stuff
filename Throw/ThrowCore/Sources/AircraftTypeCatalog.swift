import Foundation

public enum AircraftWakeCategory: String, Hashable, Sendable {
    case light = "L"
    case medium = "M"
    case heavy = "H"
    case superHeavy = "J"
}

public struct AircraftTypeCharacteristics: Hashable, Sendable {
    public let airframeCode: Character
    public let engineCode: Character
    public let wakeCategory: AircraftWakeCategory?

    public init(
        airframeCode: Character,
        engineCode: Character,
        wakeCategory: AircraftWakeCategory?,
    ) {
        self.airframeCode = airframeCode
        self.engineCode = engineCode
        self.wakeCategory = wakeCategory
    }
}

/// The compact, bundled lookup from ICAO designator to physical characteristics.
public struct AircraftTypeCatalog: Sendable {
    public static let bundled: AircraftTypeCatalog = {
        do {
            guard let url = Bundle.module.url(
                forResource: "aircraft-types-v1",
                withExtension: "json",
            ) else {
                preconditionFailure("ThrowCore is missing aircraft-types-v1.json")
            }
            return try AircraftTypeCatalog(data: Data(contentsOf: url))
        } catch {
            preconditionFailure("ThrowCore's aircraft type catalog is invalid: \(error)")
        }
    }()

    private let entries: [String: AircraftTypeCharacteristics]

    public init(data: Data) throws {
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.version == 1 else { throw AircraftTypeCatalogError.unsupportedVersion }
        var decoded: [String: AircraftTypeCharacteristics] = [:]
        for (designator, record) in archive.types {
            guard let type = AircraftTypeDesignator(rawValue: designator),
                  record.description.count == 3,
                  let airframe = record.description.first,
                  let engine = record.description.last,
                  record.wake == "-" || AircraftWakeCategory(rawValue: record.wake) != nil
            else { throw AircraftTypeCatalogError.invalidRecord }
            decoded[type.rawValue] = AircraftTypeCharacteristics(
                airframeCode: airframe,
                engineCode: engine,
                wakeCategory: AircraftWakeCategory(rawValue: record.wake),
            )
        }
        entries = decoded
    }

    public func characteristics(
        for designator: AircraftTypeDesignator,
    ) -> AircraftTypeCharacteristics? {
        entries[designator.rawValue]
    }

    private struct Archive: Decodable {
        let version: Int
        let types: [String: Record]
    }

    private struct Record: Decodable {
        let description: String
        let wake: String

        enum CodingKeys: String, CodingKey {
            case description = "d"
            case wake = "w"
        }
    }
}

public enum AircraftTypeCatalogError: Error, Equatable, Sendable {
    case unsupportedVersion
    case invalidRecord
}
