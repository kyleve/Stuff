import Foundation

/// A stationary camera's configuration. A sequence freezes a copy before its first slot.
public struct CaptureSettings: Codable, Equatable, Sendable {
    public var site: Site
    public var sunrise: Window
    public var sunset: Window
    public var camera: Camera
    public var recipe: ImageRecipe

    public static let standard = Self(
        site: .sanFrancisco,
        sunrise: .standard,
        sunset: .standard,
        camera: .standard,
        recipe: .original,
    )

    public struct Site: Codable, Equatable, Sendable {
        public var latitude: Double
        public var longitude: Double
        public var timeZoneIdentifier: String
        public static let sanFrancisco = Self(
            latitude: 37.789,
            longitude: -122.393,
            timeZoneIdentifier: "America/Los_Angeles",
        )
    }

    public struct Window: Codable, Equatable, Sendable {
        public var minutesBefore: Int
        public var minutesAfter: Int
        public var intervalMinutes: Int
        public static let standard = Self(minutesBefore: 30, minutesAfter: 30, intervalMinutes: 5)
    }

    public struct Camera: Codable, Equatable, Sendable {
        public enum Lens: String, Codable, CaseIterable,
            Sendable { case main, ultraWide, telephoto }
        public var lens: Lens
        public var zoom: Double
        public var exposureBias: Float
        public static let standard = Self(lens: .main, zoom: 1, exposureBias: 0)
    }

    public func validate() throws {
        guard site.latitude.isFinite, (-90 ... 90).contains(site.latitude),
              site.longitude.isFinite, (-180 ... 180).contains(site.longitude),
              TimeZone(identifier: site.timeZoneIdentifier) != nil,
              camera.zoom.isFinite, (1 ... 10).contains(camera.zoom),
              camera.exposureBias.isFinite, (-3 ... 3).contains(camera.exposureBias)
        else { throw DaylightError.invalidSettings }
        for window in [sunrise, sunset] {
            guard (0 ... 180).contains(window.minutesBefore),
                  (0 ... 180).contains(window.minutesAfter),
                  (1 ... 60).contains(window.intervalMinutes)
            else { throw DaylightError.invalidSettings }
        }
        try recipe.validate()
    }
}
