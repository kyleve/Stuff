#if DEBUG
    import Testing
    @testable import WhereUI

    @MainActor
    struct RankingAnimationLabModelTests {
        @Test func everyPlayProducesTheNextOvertake() {
            let model = RankingAnimationLabModel()
            model.presentation.updateReconciliationTarget(.init(
                counts: model.current,
                year: RankingAnimationLabModel.year,
                isVisible: true,
            ))

            model.playNextOvertake()
            var reconciliation = LocationCardsPresentationModel.ReconciliationID(
                counts: model.current,
                year: RankingAnimationLabModel.year,
                isVisible: true,
            )
            model.presentation.updateReconciliationTarget(reconciliation)
            #expect(model.current.map(\.region) == [.newYork, .california])
            #expect(model.current.first?.days == 129)
            #expect(model.presentation.willOvertake(reconciliation))
            #expect(model.presentation.reconcile(reconciliation) != nil)

            model.playNextOvertake()
            reconciliation = LocationCardsPresentationModel.ReconciliationID(
                counts: model.current,
                year: RankingAnimationLabModel.year,
                isVisible: true,
            )
            model.presentation.updateReconciliationTarget(reconciliation)
            #expect(model.current.map(\.region) == [.california, .newYork])
            #expect(model.current.first?.days == 130)
            #expect(model.presentation.willOvertake(reconciliation))
            #expect(model.presentation.reconcile(reconciliation) != nil)
        }
    }
#endif
