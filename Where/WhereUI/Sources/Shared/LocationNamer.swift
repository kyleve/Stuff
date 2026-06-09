import CoreLocation
import Foundation
import WhereCore

/// The human-readable pieces of a reverse-geocoded coordinate, and the rule
/// for turning them into a single "City, Country" label. Split out from the
/// geocoder so the formatting is a pure, testable value (constructing real
/// `CLPlacemark`s is impractical in unit tests).
struct PlaceComponents: Equatable {
    var locality: String?
    var area: String?
    var country: String?

    /// A compact label: the most specific available place, qualified by
    /// country. Prefers the city (`locality`), falling back to the state /
    /// province (`area`); returns `nil` only when nothing is known.
    var displayName: String? {
        guard let primary = locality ?? area else { return country }
        guard let country else { return primary }
        return "\(primary), \(country)"
    }
}

extension PlaceComponents {
    init(placemark: CLPlacemark) {
        self.init(
            locality: placemark.locality,
            area: placemark.administrativeArea,
            country: placemark.country,
        )
    }
}

/// Reverse-geocodes coordinates into place names for the Elsewhere views,
/// caching results on a coarse grid so nearby points share one lookup and the
/// system geocoder isn't hammered. Concurrent requests for the same grid cell
/// coalesce onto a single in-flight task.
///
/// Failures (offline, rate-limited, mid-ocean) resolve to `nil` and aren't
/// cached, so a later attempt can succeed. This is best-effort sugar on top of
/// the coordinates the app already stores; nothing depends on it resolving.
actor LocationNamer {
    static let shared = LocationNamer()

    /// ~0.05° (~5–6 km) buckets: fine enough to separate cities, coarse
    /// enough that a day's worth of jitter around one place hits a single
    /// cache entry (and a single geocode).
    private static let gridPrecision = 20.0

    private struct GridKey: Hashable {
        let latBucket: Int
        let lngBucket: Int
    }

    private var cache: [GridKey: String] = [:]
    private var inFlight: [GridKey: Task<String?, Never>] = [:]

    private func key(for coordinate: Coordinate) -> GridKey {
        GridKey(
            latBucket: Int((coordinate.latitude * Self.gridPrecision).rounded()),
            lngBucket: Int((coordinate.longitude * Self.gridPrecision).rounded()),
        )
    }

    func name(for coordinate: Coordinate) async -> String? {
        let key = key(for: coordinate)
        if let cached = cache[key] { return cached }
        if let existing = inFlight[key] { return await existing.value }

        let task = Task { await Self.reverseGeocode(coordinate) }
        inFlight[key] = task
        let name = await task.value
        inFlight[key] = nil
        if let name { cache[key] = name }
        return name
    }

    /// Creates a throwaway `CLGeocoder` per call (sidestepping its
    /// one-request-at-a-time constraint) and maps the first placemark to a
    /// label. Returns `nil` on any failure.
    private static func reverseGeocode(_ coordinate: Coordinate) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        else { return nil }
        return PlaceComponents(placemark: placemark).displayName
    }
}
