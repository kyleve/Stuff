import Observation
import SwiftUI

/// Runs the one visibility-aware delay that releases Location-card counts,
/// ranking order, flourish, persistence, and haptic feedback together.
struct LocationCardsReconciliationModifier: ViewModifier {
    let current: [RegionDays]
    let year: Int
    let isVisible: Bool
    let presentation: LocationCardsPresentationModel
    let motion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion

    /// Current motion stays outside the task identity so an accessibility
    /// change does not restart the fixed reveal delay.
    @State private var releaseMotion =
        WhereStylesheet.LocationCardStackStyle.OvertakeMotion.standard
    @Environment(\.stylesheet.card.dayCount.revealDelay) private var revealDelay

    private var reconciliationID: LocationCardsPresentationModel.ReconciliationID {
        LocationCardsPresentationModel.ReconciliationID(
            counts: current,
            year: year,
            isVisible: isVisible,
        )
    }

    func body(content: Content) -> some View {
        let releasedID = presentation.lastReleasedOvertakeID
        content
            .onChange(of: motion, initial: true) { _, motion in
                releaseMotion = motion
            }
            .onChange(of: reconciliationID, initial: true) { _, reconciliation in
                presentation.updateReconciliationTarget(reconciliation)
            }
            .task(id: reconciliationID) {
                let reconciliation = reconciliationID
                guard reconciliation.isVisible else { return }
                do {
                    try await Task.sleep(for: revealDelay)
                    try Task.checkCancellation()
                    try await waitForReleasedOvertakeToFinish()
                } catch is CancellationError {
                    return
                } catch {
                    assertionFailure("Unexpected Location-card reveal delay failure: \(error)")
                    return
                }
                release(
                    reconciliation,
                    overtakeMotion: releaseMotion,
                )
            }
            // Reconciliation IDs change when a newer report restarts the
            // 500 ms gate. Keep completion on the released event's own key so
            // that cancellation cannot strand or replace its active frames.
            .task(id: releasedID) {
                await finishReleasedOvertake(id: releasedID)
            }
            .sensoryFeedback(
                .impact(weight: .light),
                trigger: presentation.feedbackTrigger,
            )
    }

    private func release(
        _ reconciliation: LocationCardsPresentationModel.ReconciliationID,
        overtakeMotion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion,
    ) {
        let event = presentation.reconcile(
            reconciliation,
            overtakeMotion: overtakeMotion,
        )
        if let event, overtakeMotion.usesSpatialMotion == false {
            finishOvertake(id: event.id)
        }
    }

    private func finishReleasedOvertake(id: LocationCardsPresentationModel.OvertakeID?) async {
        guard let id,
              let movement = presentation.overtakeMovement,
              movement.id == id,
              let releasedMotion = movement.releasedMotion
        else { return }
        do {
            if releasedMotion.usesSpatialMotion {
                try await Task.sleep(for: .seconds(releasedMotion.duration))
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            return
        } catch {
            assertionFailure("Unexpected Location-card overtake wait failure: \(error)")
            return
        }
        finishOvertake(id: id)
    }

    func waitForReleasedOvertakeToFinish() async throws {
        guard presentation.overtakeMovement?.releasedMotion != nil else { return }
        let releasedStates = Observations {
            presentation.overtakeMovement?.releasedMotion != nil
        }
        for await isReleased in releasedStates {
            try Task.checkCancellation()
            guard isReleased else { return }
        }
        // `Observations` ends its iteration when its consumer is cancelled.
        // Preserve throwing cancellation semantics for the reconciliation task.
        try Task.checkCancellation()
    }

    private func finishOvertake(id: LocationCardsPresentationModel.OvertakeID) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentation.finishOvertakeMovement(id: id)
        }
    }
}

extension View {
    func reconcilesLocationCards(
        current: [RegionDays],
        year: Int,
        isVisible: Bool,
        presentation: LocationCardsPresentationModel,
        motion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion,
    ) -> some View {
        modifier(LocationCardsReconciliationModifier(
            current: current,
            year: year,
            isVisible: isVisible,
            presentation: presentation,
            motion: motion,
        ))
    }
}
