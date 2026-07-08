import Foundation

/// A longitudinal extent that may cross the antimeridian (±180°).
///
/// Unlike a plain `max − min`, this is the *shortest* arc enclosing a set
/// of longitudes, so geometry clustered near ±180° (e.g. Alaska's
/// Aleutians, which run from ~+172° east across the 180th meridian to
/// ~−130°) frames as a tight arc out in the Bering Sea instead of a
/// near-global span centered on the opposite side of the planet.
///
/// Used by the developer region-map viewer to frame its map camera.
/// Latitude has no such wrap, so callers pair this with `BoundingBox` for
/// the latitude extent; RegionKit stays UI-free, so the MapKit conversion
/// happens in the UI layer.
public struct LongitudeSpan: Hashable, Sendable {
    /// Center longitude of the arc, normalized to [−180°, 180°].
    public let center: Double
    /// Angular width of the arc in degrees, in [0°, 360°] (`0` only when
    /// every longitude is identical).
    public let degrees: Double

    public init(center: Double, degrees: Double) {
        self.center = center
        self.degrees = degrees
    }
}

extension LongitudeSpan {
    /// The shortest arc enclosing every longitude in `longitudes`, or
    /// `nil` when the sequence is empty.
    ///
    /// Sorts the longitudes around the −180°…180° circle and finds the
    /// widest empty gap between adjacent values (including the wrap from
    /// the largest back to the smallest across the antimeridian). The
    /// enclosing arc is the complement of that gap, so a cluster straddling
    /// ±180° is recognized as contiguous rather than spanning the globe.
    public static func enclosing(_ longitudes: some Sequence<Double>) -> LongitudeSpan? {
        let sorted = longitudes.sorted()
        guard let smallest = sorted.first, let largest = sorted.last else { return nil }

        // Seed with the wrap gap (largest → east across ±180° → smallest);
        // any wider interior gap replaces it as the "empty" arc, and the
        // occupied arc begins at the longitude just past that gap.
        var widestGap = (smallest + 360) - largest
        var arcStart = smallest
        for (lower, upper) in zip(sorted, sorted.dropFirst()) where upper - lower > widestGap {
            widestGap = upper - lower
            arcStart = upper
        }

        let degrees = 360 - widestGap
        return LongitudeSpan(center: normalized(arcStart + degrees / 2), degrees: degrees)
    }

    /// Wraps an arbitrary longitude into the [−180°, 180°] range.
    private static func normalized(_ longitude: Double) -> Double {
        let wrapped = longitude.truncatingRemainder(dividingBy: 360)
        if wrapped > 180 { return wrapped - 360 }
        if wrapped < -180 { return wrapped + 360 }
        return wrapped
    }
}
