import Foundation
import RegionKit
import WhereCore

/// Extracts a complete GPS window without thinning or inventing observations.
/// Replacement identities preserve duplicate conflicts and UUID tie ordering.
/// Coordinates can retain their geography or rotate together to preserve distances.
/// A constant date shift preserves gaps; calendar-sensitive cases need a suitable start.
struct FlightFixtureExporter {
    struct Configuration: Decodable {
        enum CoordinateMode: String, Decodable {
            case rotate, preserve
        }

        let backupPath: String
        let from: Date
        let until: Date
        let now: Date
        let replacementStart: Date
        let coordinateMode: CoordinateMode?
        let replacementOrigin: Coordinate?
        let typeName: String
        let outputPath: String

        /// Existing configurations rotate. Keeping original coordinates requires
        /// an explicit mode; an absent rotation origin must never select it.
        func coordinateTransform() throws -> CoordinateTransform {
            switch coordinateMode ?? .rotate {
                case .rotate:
                    guard let replacementOrigin else { throw ExportError.missingReplacementOrigin }
                    return .rotate(origin: replacementOrigin)
                case .preserve:
                    guard replacementOrigin == nil
                    else { throw ExportError.unexpectedReplacementOrigin }
                    return .preserve
            }
        }
    }

    enum CoordinateTransform: Equatable {
        case rotate(origin: Coordinate)
        case preserve
    }

    enum ExportError: Error, Equatable {
        case invalidWindow, invalidCoordinate, noSamples, invalidTypeName
        case missingReplacementOrigin, unexpectedReplacementOrigin
    }

    let originalSamples: [LocationSample]
    let samples: [LocationSample]
    let now: Date
    let sampleIDs: [LocationSample.ID: LocationSample.ID]
    let deviceIDs: [RecordingDeviceID: RecordingDeviceID]
    private let dateShift: TimeInterval
    private let coordinateTransform: CoordinateTransform

    init(
        samples input: [LocationSample],
        from: Date,
        until: Date,
        now: Date,
        replacementStart: Date,
        coordinateTransform: CoordinateTransform,
    ) throws {
        guard [from, until, now, replacementStart].allSatisfy(\.timeIntervalSince1970.isFinite),
              from < until, now >= from else { throw ExportError.invalidWindow }
        let selected = input
            .filter { $0.source.isGPS && $0.timestamp >= from && $0.timestamp < until }
        guard let anchor = selected.min(by: {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.id.uuidString < $1.id.uuidString
        }) else { throw ExportError.noSamples }
        guard selected.allSatisfy({ Self.isValid($0.coordinate) })
        else { throw ExportError.invalidCoordinate }
        let rotation: Rotation?
        switch coordinateTransform {
            case let .rotate(origin):
                guard Self.isValid(origin) else { throw ExportError.invalidCoordinate }
                rotation = Rotation(from: anchor.coordinate, to: origin)
            case .preserve:
                rotation = nil
        }
        let sampleIDs = Dictionary(uniqueKeysWithValues: Set(selected.map(\.id))
            .sorted { $0.uuidString < $1.uuidString }
            .enumerated().map { index, sampleID in
                (sampleID, Self.replacementID(index + 1, namespace: 0))
            })
        let deviceIDs =
            Dictionary(uniqueKeysWithValues: Set(selected.compactMap(\.recordingDeviceID))
                    .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
                    .enumerated().map { index, deviceID in
                        (
                            deviceID,
                            RecordingDeviceID(rawValue: Self.replacementID(index + 1, namespace: 1))
                        )
                    })
        let shift = replacementStart.timeIntervalSince(from)
        originalSamples = selected
        self.coordinateTransform = coordinateTransform
        self.sampleIDs = sampleIDs
        self.deviceIDs = deviceIDs
        dateShift = shift
        self.now = now.addingTimeInterval(shift)
        samples = selected.map { sample in
            LocationSample(
                id: sampleIDs[sample.id]!,
                timestamp: sample.timestamp.addingTimeInterval(shift),
                coordinate: rotation.map { $0.apply(sample.coordinate) } ?? sample.coordinate,
                horizontalAccuracy: sample.horizontalAccuracy,
                source: sample.source,
                recordingDeviceID: sample.recordingDeviceID.map { deviceIDs[$0]! },
                motion: sample.motion,
            )
        }
    }

    func shifted(_ date: Date) -> Date {
        date.addingTimeInterval(dateShift)
    }

    /// The generated file omits the input path and identifies its coordinate mode.
    /// It is ordinary Swift so CI needs no archive, decoder, or export configuration.
    func swiftSource(typeName: String) throws -> String {
        guard typeName.range(of: "^[A-Z][A-Za-z0-9]*$", options: .regularExpression) != nil,
              typeName != "Any", typeName != "Self"
        else { throw ExportError.invalidTypeName }
        let points = samples.map { sample in
            let device = sample.recordingDeviceID.map {
                "RecordingDeviceID(rawValue: UUID(uuidString: \"\($0.rawValue.uuidString)\")!)"
            } ?? "nil"
            return """
                    LocationSample(
                        id: UUID(uuidString: "\(sample.id.uuidString)")!,
                        timestamp: Date(timeIntervalSince1970: \(Self
                .number(sample.timestamp.timeIntervalSince1970))),
                        coordinate: Coordinate(latitude: \(Self
                .number(sample.coordinate.latitude)), longitude: \(Self
                .number(sample.coordinate.longitude))),
                        horizontalAccuracy: \(Self.number(sample.horizontalAccuracy)),
                        source: .\(sample.source.discriminator),
                        recordingDeviceID: \(device),
                        motion: \(Self.motionSource(sample.motion)),
                    ),
            """
        }.joined(separator: "\n")
        let coordinateDescription = switch coordinateTransform {
            case .rotate: "rotated coordinates"
            case .preserve: "original recorded coordinates (not relocated)"
        }
        return """
        import Foundation
        import RegionKit
        import WhereCore

        /// A complete recorded GPS window with shifted dates, replacement IDs,
        /// and \(coordinateDescription). Expected behavior is defined in the regression tests.
        enum \(typeName) {
            static let now = Date(timeIntervalSince1970: \(Self.number(now.timeIntervalSince1970)))
            static let samples: [LocationSample] = [
        \(points)
            ]
        }

        """
    }

    private static func replacementID(_ number: Int, namespace: Int) -> UUID {
        UUID(uuidString: String(format: "%08d-0000-0000-0000-%012d", namespace, number))!
    }

    private static func isValid(_ coordinate: Coordinate) -> Bool {
        coordinate.latitude.isFinite && coordinate.longitude.isFinite
            && (-90 ... 90).contains(coordinate.latitude)
            && (-180 ... 180).contains(coordinate.longitude)
    }

    private static func number(_ value: Double) -> String {
        if value.isNaN { return ".nan" }
        if value == .infinity { return ".infinity" }
        if value == -.infinity { return "-.infinity" }
        return String(value)
    }

    private static func motionSource(_ motion: LocationMotion?) -> String {
        guard let motion else { return "nil" }
        let speed = motion.speed.map {
            "LocationMotion.Speed(metersPerSecond: \(number($0.metersPerSecond)), accuracyMetersPerSecond: \(number($0.accuracyMetersPerSecond)))"
        } ?? "nil"
        let altitude = motion.altitude.map {
            "LocationMotion.Altitude(meters: \(number($0.meters)), accuracyMeters: \(number($0.accuracyMeters)))"
        } ?? "nil"
        return "LocationMotion(speed: \(speed), altitude: \(altitude))"
    }

    /// Orthonormal Earth-centered frames avoid a flat latitude/longitude translation,
    /// which would distort long routes and fail at the date line or near the poles.
    private struct Rotation {
        struct Vector {
            let x: Double
            let y: Double
            let z: Double

            func dot(_ other: Self) -> Double {
                x * other.x + y * other.y + z * other.z
            }
        }

        struct Frame {
            let up: Vector
            let east: Vector
            let north: Vector

            init(_ coordinate: Coordinate) {
                let lat = coordinate.latitude * .pi / 180
                let lon = coordinate.longitude * .pi / 180
                up = Vector(x: cos(lat) * cos(lon), y: cos(lat) * sin(lon), z: sin(lat))
                east = Vector(x: -sin(lon), y: cos(lon), z: 0)
                north = Vector(x: -sin(lat) * cos(lon), y: -sin(lat) * sin(lon), z: cos(lat))
            }
        }

        let source: Frame
        let target: Frame

        init(from: Coordinate, to: Coordinate) {
            source = Frame(from)
            target = Frame(to)
        }

        func apply(_ coordinate: Coordinate) -> Coordinate {
            let point = Frame(coordinate).up
            let up = point.dot(source.up)
            let east = point.dot(source.east)
            let north = point.dot(source.north)
            let x = up * target.up.x + east * target.east.x + north * target.north.x
            let y = up * target.up.y + east * target.east.y + north * target.north.y
            let z = up * target.up.z + east * target.east.z + north * target.north.z
            return Coordinate(
                latitude: atan2(z, hypot(x, y)) * 180 / .pi,
                longitude: atan2(y, x) * 180 / .pi,
            )
        }
    }
}
