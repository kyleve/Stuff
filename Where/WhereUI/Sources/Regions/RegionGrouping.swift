import RegionKit

/// The three-way split the region-selection surfaces share: a stable reference
/// set (`primary` — your tracked regions in the manual-day form, your picks in
/// the primary-region picker), the non-primary regions used in the selected
/// year, and everything else. `.other` is never surfaced in ``usedThisYear`` —
/// it's the catch-all, so it always lands in ``other``.
///
/// Pure and order-preserving: `primary` keeps the order it was given (pick
/// order), while `usedThisYear` and `other` follow `available`'s (catalog)
/// order. Membership is a function of `primary` + `usedThisYear` only — not the
/// live selection — so rows don't jump between groups as they're toggled.
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
