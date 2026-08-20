#if DEBUG
    import Testing
    @testable import WhereUI

    @MainActor
    struct RankingAnimationLabModelTests {
        @Test func playAlternatesTheWinningRegion() {
            let model = RankingAnimationLabModel()

            model.playNextOvertake()
            #expect(model.current.map(\.region) == [.newYork, .california])
            #expect(model.current.first?.days == 129)

            model.playNextOvertake()
            #expect(model.current.map(\.region) == [.california, .newYork])
            #expect(model.current.first?.days == 130)
        }

        @Test func resetRestoresTheFixtureAndPresentationBaseline() {
            let model = RankingAnimationLabModel()
            let originalPresentation = model.presentation
            model.playNextOvertake()

            model.resetDemo()

            #expect(model.current == RankingAnimationLabModel.initialRanking)
            #expect(model.presentation !== originalPresentation)
            #expect(model.presentation.presented(model.current) == model.current)
        }
    }
#endif
