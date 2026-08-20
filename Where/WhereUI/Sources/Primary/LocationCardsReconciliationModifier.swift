import SwiftUI

/// Runs the one visibility-aware delay that releases Location-card counts,
/// ranking order, flourish, persistence, and haptic feedback together.
struct LocationCardsReconciliationModifier: ViewModifier {
    let current: [RegionDays]
    let year: Int
    let isVisible: Bool
    let presentation: LocationCardsPresentationModel
    var motionOverride: WhereStylesheet.LocationCardStackStyle.OvertakeMotion?

    @Environment(\.stylesheet) private var stylesheet

    private var reconciliationID: LocationCardsPresentationModel.ReconciliationID {
        LocationCardsPresentationModel.ReconciliationID(
            counts: current,
            year: year,
            isVisible: isVisible,
        )
    }

    private var motion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion {
        motionOverride ?? stylesheet.locationCardStack.overtake
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: reconciliationID, initial: true) { _, reconciliation in
                presentation.updateReconciliationTarget(reconciliation)
            }
            .task(id: reconciliationID) {
                let reconciliation = reconciliationID
                guard reconciliation.isVisible else { return }
                do {
                    try await Task.sleep(for: stylesheet.card.dayCount.revealDelay)
                    try Task.checkCancellation()
                } catch is CancellationError {
                    return
                } catch {
                    assertionFailure("Unexpected Location-card reveal delay failure: \(error)")
                    return
                }

                let willOvertake = presentation.willOvertake(reconciliation)
                if willOvertake, let animation = motion.layoutAnimation {
                    withAnimation(animation) {
                        presentation.reconcile(reconciliation)
                    }
                } else {
                    presentation.reconcile(reconciliation)
                }
            }
            .sensoryFeedback(
                .impact(weight: .light),
                trigger: presentation.feedbackTrigger,
            )
    }
}

extension View {
    func reconcilesLocationCards(
        current: [RegionDays],
        year: Int,
        isVisible: Bool,
        presentation: LocationCardsPresentationModel,
        motionOverride: WhereStylesheet.LocationCardStackStyle.OvertakeMotion? = nil,
    ) -> some View {
        modifier(LocationCardsReconciliationModifier(
            current: current,
            year: year,
            isVisible: isVisible,
            presentation: presentation,
            motionOverride: motionOverride,
        ))
    }
}
