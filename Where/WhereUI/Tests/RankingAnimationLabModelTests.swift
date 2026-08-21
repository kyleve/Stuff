#if DEBUG
    import Testing
    @testable import WhereUI

    @MainActor
    struct RankingAnimationLabModelTests {
        @Test func everyPlayQueuesTheNextOvertakeUntilTheActiveOneFinishes() throws {
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
            let firstEvent = try #require(model.presentation.reconcile(
                reconciliation,
                overtakeMotion: .standard,
            ))

            model.playNextOvertake()
            reconciliation = LocationCardsPresentationModel.ReconciliationID(
                counts: model.current,
                year: RankingAnimationLabModel.year,
                isVisible: true,
            )
            model.presentation.updateReconciliationTarget(reconciliation)
            #expect(model.current.map(\.region) == [.california, .newYork])
            #expect(model.current.first?.days == 130)
            #expect(model.presentation.willOvertake(reconciliation) == false)
            #expect(model.presentation.overtakeMovement?.sequence == 1)
            #expect(model.presentation.overtakeMovement?.releasedMotion == .standard)
            #expect(model.presentation.reconcile(
                reconciliation,
                overtakeMotion: .standard,
            ) == nil)

            model.presentation.finishOvertakeMovement(sequence: firstEvent.sequence)

            #expect(model.presentation.willOvertake(reconciliation))
            #expect(model.presentation.overtakeMovement == .init(
                sequence: 2,
                fromOrder: [.newYork, .california],
                toOrder: [.california, .newYork],
                phase: .pending,
            ))
            #expect(model.presentation.reconcile(
                reconciliation,
                overtakeMotion: .standard,
            ) != nil)
        }
    }
#endif
