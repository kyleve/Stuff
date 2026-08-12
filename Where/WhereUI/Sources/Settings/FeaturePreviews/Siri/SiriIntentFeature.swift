import SFSafeSymbols
import SwiftUI

/// One App Intent demonstrated by the Siri feature gallery. Kept separate from
/// the screen's searchable items because Spotlight is searchable there without
/// pretending to be a spoken intent.
enum SiriIntentFeature: CaseIterable, Hashable {
    case todayRegions
    case daysInRegion
    case regionOnDate
    case recentActivity
    case logDay
    case logTrip

    var item: SiriFeaturesView.Item {
        switch self {
            case .todayRegions: .todayRegions
            case .daysInRegion: .daysInRegion
            case .regionOnDate: .regionOnDate
            case .recentActivity: .recentActivity
            case .logDay: .logDay
            case .logTrip: .logTrip
        }
    }

    var systemSymbol: SFSymbol {
        switch self {
            case .todayRegions: .locationFill
            case .daysInRegion: .calendar
            case .regionOnDate: .calendarBadgeClock
            case .recentActivity: .sparkles
            case .logDay: .mappinAndEllipse
            case .logTrip: .airplane
        }
    }

    var request: String {
        switch self {
            case .todayRegions: String(localized: .settingsExploreSiriTodayRequest)
            case .daysInRegion: String(localized: .settingsExploreSiriDaysRequest)
            case .regionOnDate: String(localized: .settingsExploreSiriDateRequest)
            case .recentActivity: String(localized: .settingsExploreSiriRecentRequest)
            case .logDay: String(localized: .settingsExploreSiriLogDayRequest)
            case .logTrip: String(localized: .settingsExploreSiriLogTripRequest)
        }
    }

    var response: String {
        switch self {
            case .todayRegions: String(localized: .settingsExploreSiriTodayResponse)
            case .daysInRegion: String(localized: .settingsExploreSiriDaysResponse)
            case .regionOnDate: String(localized: .settingsExploreSiriDateResponse)
            case .recentActivity: String(localized: .settingsExploreSiriRecentResponse)
            case .logDay: String(localized: .settingsExploreSiriLogDayResponse)
            case .logTrip: String(localized: .settingsExploreSiriLogTripResponse)
        }
    }
}
