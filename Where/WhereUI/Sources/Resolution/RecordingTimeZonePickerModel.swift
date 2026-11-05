import Foundation
import Observation

/// Searches explicit zone names without preferring this phone's current zone.
@MainActor
@Observable
final class RecordingTimeZonePickerModel {
    var search = ""
    private static let zones = TimeZone.knownTimeZoneIdentifiers
        .compactMap(TimeZone.init(identifier:))
        .sorted { $0.identifier < $1.identifier }

    var zones: [TimeZone] {
        guard !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self.zones
        }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.zones.filter {
            $0.identifier.localizedStandardContains(query) ||
                WhereFormat.recordingTimeZone($0).localizedStandardContains(query)
        }
    }
}
