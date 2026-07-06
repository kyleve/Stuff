import CoreLocation
import Foundation
import MapKit
import WhereCore

/// The human-readable pieces of a reverse-geocoded coordinate, and the rule
/// for turning them into a single "City, Country" label. Split out from the
/// geocoder so the formatting is a pure, testable value (constructing real
/// MapKit results is impractical in unit tests).
struct PlaceComponents: Equatable {
    var city: String?
    var country: String?

    /// A compact label: the city qualified by country. Falls back to whichever
    /// single piece is known; returns `nil` only when neither is.
    var displayName: String? {
        guard let city else { return country }
        guard let country else { return city }
        return "\(city), \(country)"
    }
}

extension PlaceComponents {
    /// iOS 26's MapKit geocoder folds the old `CLPlacemark` fields into
    /// formatted strings; `cityName` and `regionName` (the country) are the two
    /// pieces this compact teaser needs.
    init(_ representations: MKAddressRepresentations) {
        self.init(city: representations.cityName, country: representations.regionName)
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

    /// Reverse-geocodes `coordinate` with MapKit and maps the first result to a
    /// label, returning `nil` on any failure. Runs on the main actor because
    /// `MKReverseGeocodingRequest` vends its (non-`Sendable`) `MKMapItem`s
    /// there; only the resulting `String` crosses back.
    @MainActor
    private static func reverseGeocode(_ coordinate: Coordinate) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        guard
            let representations = try? await request.mapItems.first?.addressRepresentations
        else { return nil }
        return PlaceComponents(representations).displayName
    }
}
