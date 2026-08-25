import Foundation

public struct GeographyLayerInput: Sendable {
    public init() {}
}

public protocol GeographyDataSource: Sendable {
    func data() async throws -> Data
}

public struct BundledGeographyDataSource: GeographyDataSource {
    public init() {}

    @concurrent public func data() async throws -> Data {
        guard let url = Bundle.module.url(
            forResource: "geography-v2",
            withExtension: "json",
        ) else {
            throw GeographyDataError.resourceMissing
        }
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GeographyDataError.resourceMissing
        }
    }
}

public struct GeographyLayerRuntime: ProjectionLayerRuntime {
    private let dataSource: any GeographyDataSource

    public init(dataSource: any GeographyDataSource) {
        self.dataSource = dataSource
    }

    @concurrent public func frame(for _: GeographyLayerInput) async throws -> LayerFrame {
        let data = try await dataSource.data()
        let lines = try await GeographyArchiveDecoder.decode(data)
        return LayerFrame(
            layerID: .geography,
            observedAt: Date(timeIntervalSince1970: 0),
            content: .geographicLines(lines),
        )
    }
}

public enum GeographyArchiveDecoder {
    @concurrent public static func decode(_ data: Data) async throws -> [GeographicPolyline] {
        do {
            try Task.checkCancellation()
            let archive = try JSONDecoder().decode(Archive.self, from: data)
            try Task.checkCancellation()
            return try archive.lines()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GeographyDataError {
            throw error
        } catch {
            throw GeographyDataError.invalidArchive
        }
    }
}

extension GeographyArchiveDecoder {
    fileprivate struct Archive: Decodable {
        let version: Int
        let coordinateScale: Int
        let sources: [StoredSource]
        let paths: [StoredPath]

        func lines() throws -> [GeographicPolyline] {
            guard version == 2,
                  (1 ... 1_000_000_000).contains(coordinateScale),
                  sources.isEmpty == false,
                  sources.allSatisfy(\.isValid),
                  Set(sources.map(\.id)).count == sources.count
            else {
                throw GeographyDataError.invalidArchive
            }
            var lines: [GeographicPolyline] = []
            lines.reserveCapacity(paths.count)
            for (index, path) in paths.enumerated() {
                if index.isMultiple(of: 64) {
                    try Task.checkCancellation()
                }
                try lines.append(path.polyline(scale: coordinateScale))
            }
            try Task.checkCancellation()
            return lines
        }
    }

    fileprivate struct StoredSource: Decodable {
        let id: String
        let name: String
        let release: String
        let scale: String

        var isValid: Bool {
            let idCharacters = Array(id)
            return idCharacters.isEmpty == false &&
                idCharacters.count <= 64 &&
                idCharacters.first != "-" &&
                idCharacters.last != "-" &&
                id.contains("--") == false &&
                idCharacters.allSatisfy { character in
                    character.isASCII &&
                        (character.isLowercase || character.isNumber || character == "-")
                } &&
                [name, release, scale].allSatisfy { value in
                    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                }
        }
    }

    fileprivate struct StoredPath: Decodable {
        let kind: GeographyLineKind
        let detailLevel: GeographyDetailLevel
        let bounds: [Int]
        let coordinates: [Int]

        func polyline(scale: Int) throws -> GeographicPolyline {
            try GeographyArchiveDecoder.decodePolyline(
                kind: kind,
                detailLevel: detailLevel,
                storedBounds: bounds,
                storedCoordinates: coordinates,
                coordinateScale: scale,
            )
        }
    }

    fileprivate static func decodePolyline(
        kind: GeographyLineKind,
        detailLevel: GeographyDetailLevel,
        storedBounds: [Int],
        storedCoordinates: [Int],
        coordinateScale: Int,
    ) throws -> GeographicPolyline {
        guard storedBounds.count == 4,
              storedCoordinates.count >= 4,
              storedCoordinates.count.isMultiple(of: 2)
        else {
            throw GeographyDataError.invalidArchive
        }
        let scale = Double(coordinateScale)
        let bounds = try GeographicBounds(
            southLatitude: Double(storedBounds[0]) / scale,
            westLongitude: Double(storedBounds[1]) / scale,
            northLatitude: Double(storedBounds[2]) / scale,
            eastLongitude: Double(storedBounds[3]) / scale,
        )
        var latitude = storedCoordinates[0]
        var longitude = storedCoordinates[1]
        var decoded = try [coordinate(latitude: latitude, longitude: longitude, scale: scale)]
        decoded.reserveCapacity(storedCoordinates.count / 2)
        var index = 2
        while index < storedCoordinates.count {
            if index.isMultiple(of: 512) {
                try Task.checkCancellation()
            }
            let (nextLatitude, latitudeOverflow) = latitude
                .addingReportingOverflow(storedCoordinates[index])
            let (nextLongitude, longitudeOverflow) = longitude
                .addingReportingOverflow(storedCoordinates[index + 1])
            guard latitudeOverflow == false, longitudeOverflow == false else {
                throw GeographyDataError.invalidArchive
            }
            latitude = nextLatitude
            longitude = nextLongitude
            try decoded.append(coordinate(latitude: latitude, longitude: longitude, scale: scale))
            index += 2
        }
        try Task.checkCancellation()
        return try GeographicPolyline(
            kind: kind,
            detailLevel: detailLevel,
            bounds: bounds,
            coordinates: decoded,
        )
    }

    fileprivate static func coordinate(latitude: Int, longitude: Int, scale: Double) throws
        -> GeoCoordinate
    {
        do {
            return try GeoCoordinate(
                latitude: Double(latitude) / scale,
                longitude: Double(longitude) / scale,
            )
        } catch {
            throw GeographyDataError.invalidArchive
        }
    }
}
