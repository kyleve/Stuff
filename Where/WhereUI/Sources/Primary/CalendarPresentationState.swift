import Foundation
import Observation
import WhereCore

/// View-owned zoom and rejection feedback. The native detail position owns restoration.
@MainActor @Observable
final class CalendarPresentationState {
    enum Mode: Hashable { case detail, overview }
    enum Target: Hashable {
        case month(CalendarDay)
        case estimate(CalendarDay)
        var month: CalendarDay {
            switch self {
                case let .month(month), let .estimate(month): month
            }
        }
    }

    // Completed pinch ratios relative to the start of the gesture.
    static let overviewThreshold: CGFloat = 0.8
    static let detailThreshold: CGFloat = 1.2
    var mode: Mode
    private(set) var year: Int?
    private(set) var availableMonths: Set<CalendarDay> = []
    private(set) var estimateMonth: CalendarDay?
    private(set) var rejectedTarget: Target?
    private(set) var rejectionCount = 0

    init(mode: Mode) {
        self.mode = mode
    }

    func reconcile(year: Int, availableMonths: [CalendarDay], estimateMonth: CalendarDay?) {
        if self.year != year { rejectedTarget = nil }
        self.year = year
        self.availableMonths = Set(availableMonths)
        self.estimateMonth = estimateMonth
    }

    func isAvailable(_ target: Target) -> Bool {
        switch target {
            case let .month(month): availableMonths.contains(month)
            case let .estimate(month): estimateMonth == month
        }
    }

    func expand(_ destination: Target?) -> Bool {
        guard let destination else { return false }
        guard isAvailable(destination) else {
            rejectedTarget = destination
            rejectionCount += 1
            return false
        }
        mode = .detail
        return true
    }
}
