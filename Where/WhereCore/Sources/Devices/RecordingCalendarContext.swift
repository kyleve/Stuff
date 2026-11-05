import Foundation

/// The zone name and UTC offset established for a particular observation-time interval.
/// The stored offset determines logical dates even if the system's zone database later changes.
public struct RecordingCalendarContext: Hashable, Codable, Sendable {
    public enum ValidationError: Error { case invalidOffset, invalidTimestamp }

    public let timeZone: TimeZone
    public let secondsFromGMT: Int

    public init(timeZone: TimeZone, secondsFromGMT: Int) throws {
        self.timeZone = timeZone
        self.secondsFromGMT = secondsFromGMT
        try validate()
    }

    public init(observedAt timestamp: Date, timeZone: TimeZone) throws {
        guard timestamp.timeIntervalSinceReferenceDate.isFinite
        else { throw ValidationError.invalidTimestamp }
        try self.init(timeZone: timeZone, secondsFromGMT: timeZone.secondsFromGMT(for: timestamp))
    }

    public func validate() throws {
        guard TimeZone(secondsFromGMT: secondsFromGMT) != nil
        else { throw ValidationError.invalidOffset }
    }

    public func calendar() throws -> Calendar {
        guard let zone = TimeZone(secondsFromGMT: secondsFromGMT)
        else { throw ValidationError.invalidOffset }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
}
