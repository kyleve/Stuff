import RegionKit

/// Groups regions in the manual-day and planning pickers. The user's tracked
/// regions keep their saved order. Regions used in the selected year and all
/// remaining choices keep catalog order. The catch-all `.other` is excluded
/// from ``usedThisYear``.
struct RegionGrouping: Equatable {
    /// The reference set (your regions / picks), filtered to `available`.
    let primary: [Region]
    /// Non-primary regions used this year (never `.other`).
    let usedThisYear: [Region]
    /// Everything else (includes `.other`).
    let other: [Region]

    init(available: [Region], primary: [Region], usedThisYear: Set<Region>) {
        let offered = Set(available)
        let primarySet = Set(primary)
        self.primary = primary.filter { offered.contains($0) }
        self.usedThisYear = available.filter {
            Self.isUsedThisYear($0, usedThisYear: usedThisYear, primary: primarySet)
        }
        other = available.filter {
            !primarySet.contains($0)
                && !Self.isUsedThisYear($0, usedThisYear: usedThisYear, primary: primarySet)
        }
    }

    private static func isUsedThisYear(
        _ region: Region,
        usedThisYear: Set<Region>,
        primary: Set<Region>,
    ) -> Bool {
        region != .other && !primary.contains(region) && usedThisYear.contains(region)
    }

    /// True when both groups above "everything else" are empty, so a caller can
    /// open the collapsed "more" group up front rather than showing it empty.
    var hasNoGroupsBeforeOther: Bool {
        primary.isEmpty && usedThisYear.isEmpty
    }
}
