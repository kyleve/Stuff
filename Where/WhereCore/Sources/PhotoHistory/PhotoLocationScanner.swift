import Foundation
import RegionKit

public enum PhotoLibraryAccess: Sendable {
    case undetermined
    case limited
    case full
    case unavailable

    public var allowsReading: Bool {
        self == .limited || self == .full
    }
}

/// The identity of a historical observation deliberately omits Photos asset identifiers.
public struct PhotoPoint: Hashable, Sendable {
    public let capturedAt: Date
    public let coordinate: Coordinate

    public init(capturedAt: Date, coordinate: Coordinate) {
        self.capturedAt = capturedAt
        self.coordinate = coordinate
    }
}

public struct PhotoObservation: Sendable {
    public let point: PhotoPoint
    public let accuracy: Double?

    public init?(capturedAt: Date?, addedAt: Date?, coordinate: Coordinate?, accuracy: Double?) {
        guard let capturedAt, let addedAt, abs(addedAt.timeIntervalSince(capturedAt)) <= 300,
              let coordinate, (-90 ... 90).contains(coordinate.latitude),
              (-180 ... 180).contains(coordinate.longitude),
              accuracy.map({ $0.isFinite && $0 >= 0 }) ?? true else { return nil }
        point = PhotoPoint(capturedAt: capturedAt, coordinate: coordinate)
        self.accuracy = accuracy
    }
}

public protocol PhotoLocationReading: Sendable {
    func access(requestIfNeeded: Bool) async -> PhotoLibraryAccess
    func enumerate(
        in window: DateInterval,
        consume: @Sendable ([PhotoObservation], Int, Int) async throws -> Void,
    ) async throws
}

public struct DatedPhotoLocation: Sendable {
    public let observation: PhotoObservation
    public let day: CalendarDay
    public let region: Region

    @_spi(Testing)
    public init(observation: PhotoObservation, day: CalendarDay, region: Region) {
        self.observation = observation
        self.day = day
        self.region = region
    }
}

public struct PhotoLocationScan: Sendable {
    public let calendar: Calendar
    public let through: CalendarDay
    public let access: PhotoLibraryAccess
    public let points: [DatedPhotoLocation]

    @_spi(Testing)
    public init(
        calendar: Calendar,
        through: CalendarDay,
        access: PhotoLibraryAccess,
        points: [DatedPhotoLocation],
    ) {
        self.calendar = calendar
        self.through = through
        self.access = access
        self.points = points
    }
}

public enum PhotoScanError: Error {
    case accessChanged
    case unavailable
}

/// One worker per user-initiated scan. Only value metadata crosses the host boundary.
public actor PhotoLocationScanner {
    private var points: [PhotoPoint: DatedPhotoLocation] = [:]
    private var attributor: RegionAttributor?

    public static func scan(
        reader: any PhotoLocationReading,
        calendar: Calendar,
        now: Date,
        progress: @escaping @Sendable (Int, Int) async -> Void,
    ) async throws -> PhotoLocationScan {
        try Task.checkCancellation()
        let access = await reader.access(requestIfNeeded: true)
        try Task.checkCancellation()
        guard access.allowsReading else { throw PhotoScanError.unavailable }
        let year = calendar.component(.year, from: now)
        let bounds = DayAggregator(calendar: calendar, timeZone: calendar.timeZone)
            .yearInterval(year: year)
        let window = DateInterval(start: bounds.start, end: now)
        let worker = PhotoLocationScanner()
        try await reader.enumerate(in: window) { batch, scanned, total in
            try await worker.consume(batch, window: window, calendar: calendar)
            await progress(scanned, total)
        }
        try Task.checkCancellation()
        guard await reader.access(requestIfNeeded: false) == access
        else { throw PhotoScanError.accessChanged }
        let snapshot = await Array(worker.points.values)
        try Task.checkCancellation()
        return PhotoLocationScan(
            calendar: calendar,
            through: CalendarDay(from: now, in: calendar),
            access: access,
            points: snapshot,
        )
    }

    private func consume(
        _ batch: [PhotoObservation],
        window: DateInterval,
        calendar: Calendar,
    ) throws {
        for observation in batch {
            try Task.checkCancellation()
            let key = observation.point
            guard key.capturedAt >= window.start, key.capturedAt <= window.end else { continue }
            if let previous = points[key],
               (previous.observation.accuracy ?? .infinity) <=
               (observation.accuracy ?? .infinity)
            {
                continue
            }
            if attributor == nil {
                attributor = RegionAttributor(for: RegionCatalog.shared.all)
            }
            guard let attributor else { continue }
            points[key] = DatedPhotoLocation(
                observation: observation,
                day: CalendarDay(from: key.capturedAt, in: calendar),
                region: attributor.region(at: key.coordinate),
            )
        }
    }
}
