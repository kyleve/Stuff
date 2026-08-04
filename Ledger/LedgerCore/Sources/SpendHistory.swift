import Foundation

/// One recorded point of the cycle's cumulative on-demand spend. Persisted over
/// time so per-day / per-week spend can be derived by differencing (the API has
/// no per-range billed figure — see the module README).
public struct SpendSample: Codable, Equatable, Sendable {
    /// When the sample was taken.
    public var timestamp: Date
    /// The billing cycle this sample belongs to (samples only difference within
    /// one cycle, since `onDemand.used` resets at the boundary).
    public var cycleStart: Date?
    /// Cumulative usage-based spend so far this cycle, in cents.
    public var onDemandCents: Int

    public init(timestamp: Date, cycleStart: Date?, onDemandCents: Int) {
        self.timestamp = timestamp
        self.cycleStart = cycleStart
        self.onDemandCents = onDemandCents
    }
}

/// Per-window spend derived from the history, in cents. `nil` means "not enough
/// history yet" (no baseline near the window start), so the UI can hide it
/// rather than show a wrong number.
public struct SpendDeltas: Equatable, Sendable {
    public var todayCents: Int?
    public var thisWeekCents: Int?

    public init(todayCents: Int?, thisWeekCents: Int?) {
        self.todayCents = todayCents
        self.thisWeekCents = thisWeekCents
    }

    public var todayDollars: Double? {
        todayCents.map { Double($0) / 100 }
    }

    public var thisWeekDollars: Double? {
        thisWeekCents.map { Double($0) / 100 }
    }
}

/// Differences the cumulative on-demand total across recorded ``SpendSample``s
/// to produce today's and this-week's spend.
///
/// Because `onDemand.used` is a server-side running total, the spend between any
/// two samples is just their difference — so this captures usage even while the
/// app wasn't running, as long as a sample exists near the window's start.
/// Baselines are scoped to the current billing cycle; a window that begins
/// before the cycle started counts the whole cycle-to-date (on-demand resets at
/// the boundary anyway).
public enum SpendHistory {
    /// Today's and this-(calendar-)week's spend for `current`, given prior
    /// `samples`.
    public static func deltas(
        current: SpendSample,
        samples: [SpendSample],
        calendar: Calendar,
        now: Date,
    ) -> SpendDeltas {
        let startOfDay = calendar.startOfDay(for: now)
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfDay
        return SpendDeltas(
            todayCents: spend(since: startOfDay, current: current, samples: samples),
            thisWeekCents: spend(since: startOfWeek, current: current, samples: samples),
        )
    }

    /// Spend from `windowStart` to `current`, or `nil` when no baseline is
    /// available (insufficient history).
    static func spend(
        since windowStart: Date,
        current: SpendSample,
        samples: [SpendSample],
    ) -> Int? {
        guard let baseline = baselineCents(at: windowStart, current: current, samples: samples)
        else {
            return nil
        }
        // On-demand should only grow within a cycle; clamp against rare
        // adjustments so a delta never reads negative.
        return max(0, current.onDemandCents - baseline)
    }

    /// The cumulative on-demand cents as of `windowStart`, within `current`'s
    /// cycle. Returns 0 when the cycle itself began at/after the window (the
    /// whole cycle-to-date falls inside it), or `nil` when the window predates
    /// the cycle but no sample covers it.
    private static func baselineCents(
        at windowStart: Date,
        current: SpendSample,
        samples: [SpendSample],
    ) -> Int? {
        if let cycleStart = current.cycleStart, cycleStart >= windowStart {
            return 0
        }
        let baseline = samples
            .filter { $0.cycleStart == current.cycleStart && $0.timestamp <= windowStart }
            .max { $0.timestamp < $1.timestamp }
        return baseline?.onDemandCents
    }
}
