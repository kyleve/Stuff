import Foundation

public protocol SolarCalculating: Sendable {
    func events(on date: Date, site: CaptureSettings.Site) throws -> [SolarEvent]
}
