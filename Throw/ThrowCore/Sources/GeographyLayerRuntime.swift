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
            forResource: "geography-v1",
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
            let archive = try JSONDecoder().decode(Archive.self, from: data)
            guard archive.version == 1,
                  archive.coordinateScale > 0,
                  archive.source.name.isEmpty == false,
                  archive.source.release.isEmpty == false,
                  archive.source.scale.isEmpty == false
            else {
                throw GeographyDataError.invalidArchive
            }
            return try archive.paths.map { try $0.polyline(scale: archive.coordinateScale) }
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
        let source: Source
        let paths: [StoredPath]
    }

    fileprivate struct Source: Decodable {
        let name: String
        let release: String
        let scale: String
    }

    fileprivate struct StoredPath: Decodable {
        let kind: GeographyLineKind
        let minimumZoomTenths: Int
        let scaleRank: Int
        let bounds: [Int]
        let coordinates: [Int]

        func polyline(scale: Int) throws -> GeographicPolyline {
            guard bounds.count == 4,
                  coordinates.count >= 4,
                  coordinates.count.isMultiple(of: 2)
            else {
                throw GeographyDataError.invalidArchive
            }
            let scale = Double(scale)
            let bounds = try GeographicBounds(
                southLatitude: Double(bounds[0]) / scale,
                westLongitude: Double(bounds[1]) / scale,
                northLatitude: Double(bounds[2]) / scale,
                eastLongitude: Double(bounds[3]) / scale,
            )
            var latitude = coordinates[0]
            var longitude = coordinates[1]
            var decoded = try [coordinate(latitude: latitude, longitude: longitude, scale: scale)]
            decoded.reserveCapacity(coordinates.count / 2)
            var index = 2
            while index < coordinates.count {
                let (nextLatitude, latitudeOverflow) = latitude
                    .addingReportingOverflow(coordinates[index])
                let (nextLongitude, longitudeOverflow) = longitude
                    .addingReportingOverflow(coordinates[index + 1])
                guard latitudeOverflow == false, longitudeOverflow == false else {
                    throw GeographyDataError.invalidArchive
                }
                latitude = nextLatitude
                longitude = nextLongitude
                try decoded.append(
                    coordinate(latitude: latitude, longitude: longitude, scale: scale),
                )
                index += 2
            }
            return try GeographicPolyline(
                kind: kind,
                minimumZoomTenths: minimumZoomTenths,
                scaleRank: scaleRank,
                bounds: bounds,
                coordinates: decoded,
            )
        }

        private func coordinate(latitude: Int, longitude: Int, scale: Double) throws
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
}
