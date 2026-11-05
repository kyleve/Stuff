import Foundation
import RegionKit
import SFSafeSymbols
import WhereCore

/// Widget presentation keeps unavailable or unresolved output separate from an empty result.
enum WidgetContent<Content: Equatable>: Equatable {
    case complete(Content)
    case unavailable(WidgetHistoryStatus)
}

enum WidgetHistoryStatus: Equatable {
    case needsReview
    case unavailable

    var title: String {
        switch self {
            case .needsReview: String(localized: .widgetHistoryNeedsReview)
            case .unavailable: String(localized: .widgetHistoryUnavailable)
        }
    }

    var accessibilityValue: String {
        switch self {
            case .needsReview: String(localized: .widgetHistoryNeedsReviewDetail)
            case .unavailable: String(localized: .widgetHistoryUnavailableDetail)
        }
    }

    var symbol: SFSymbol {
        switch self {
            case .needsReview: .exclamationmarkCircle
            case .unavailable: .arrowClockwise
        }
    }
}

extension WidgetSnapshot {
    /// Preserve scope eligibility while ranking complete year counts like the app's cards.
    func rankedTotals(maxRows: Int) -> WidgetContent<[RegionDays]> {
        guard let assessment else { return .unavailable(.unavailable) }
        switch assessment.totals {
            case .needsReview: return .unavailable(.needsReview)
            case let .complete(totals):
                let report = YearReport(year: year, days: [], totals: totals)
                return .complete(Array(RegionRanking.ranked(report: report).prefix(max(
                    0,
                    maxRows,
                ))))
        }
    }

    var orderedDayRegions: WidgetContent<[Region]> {
        guard let assessment else { return .unavailable(.unavailable) }
        return switch assessment.dayRegions {
            case .needsReview: .unavailable(.needsReview)
            case let .complete(regions): .complete(Region.inCanonicalOrder(regions))
        }
    }
}
