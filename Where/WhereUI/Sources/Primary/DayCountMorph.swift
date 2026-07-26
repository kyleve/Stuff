import SwiftUI

/// How a region's day count changes on a `RegionSummaryCard` that is already on
/// screen — a passive GPS sample lands, a manual day commits, or a remote import
/// arrives, and the number the card is showing is suddenly stale.
///
/// The two halves of the effect have to agree, which is why they're picked here
/// rather than at two call sites that could drift apart: a `ContentTransition`
/// morphs only inside an animation transaction, so the transition is inert
/// without the matching animation, and Reduce Motion changes *both* (a crossfade
/// wants a plain fade curve, not the roll's).
enum DayCountMorph: Equatable {
    /// The digits roll from the old count to the new one.
    case numericRoll
    /// The Reduce-Motion fallback: the old count fades into the new one, with
    /// nothing travelling across the card.
    case crossfade

    init(reduceMotion: Bool) {
        self = reduceMotion ? .crossfade : .numericRoll
    }

    /// The transition for the count's `Text`. `days` gives the roll a direction,
    /// so a day added spins the digits up and a correction spins them down.
    func contentTransition(days: Int) -> ContentTransition {
        switch self {
            case .numericRoll: .numericText(value: Double(days))
            case .crossfade: .opacity
        }
    }

    /// The animation that drives the transition — and, in the same beat, the
    /// ambient bar reading the same count.
    func animation(_ motion: WhereStylesheet.Motion) -> Animation {
        switch self {
            case .numericRoll: motion.dayCountChange
            case .crossfade: motion.reducedDayCountChange
        }
    }
}
