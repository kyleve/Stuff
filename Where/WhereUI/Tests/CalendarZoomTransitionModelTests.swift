import SwiftUI
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct CalendarZoomTransitionModelTests {
    private let viewport = CGRect(x: 0, y: 0, width: 402, height: 800)
    private let content = CGRect(x: 0, y: 0, width: 402, height: 2000)
    private let compact = CGRect(x: 140, y: 420, width: 120, height: 100)
    private let expanded = CGRect(x: 16, y: 0, width: 370, height: 360)
    private let november = CalendarPresentationModel.Target.month(CalendarDay(
        year: 2026,
        month: 11,
        day: 1,
    ))
    private let december = CalendarPresentationModel.Target.month(CalendarDay(
        year: 2026,
        month: 12,
        day: 1,
    ))

    @Test func waitsForTheSelectedMonthToFinishScrollingBeforeMatching() throws {
        let model = CalendarZoomTransitionModel()
        model.begin(
            from: .init(
                mode: .overview,
                frames: [november: compact],
                viewport: viewport,
                content: content,
            ),
            to: .detail,
            focus: november,
        )
        model.resolve(
            destination: .init(
                mode: .detail,
                frames: [november: expanded.offsetBy(dx: 0, dy: 400)],
                viewport: viewport,
                content: content,
            ),
        )
        guard case .preparing = model.phase else {
            Issue.record("The source must stay visible while the destination scrolls")
            return
        }

        model.resolve(
            destination: .init(
                mode: .detail,
                frames: [november: expanded],
                viewport: viewport,
                content: content,
            ),
        )
        let plan = try movingPlan(model)
        let tile = try #require(plan.tiles.first)
        #expect(plan.tiles.count == 1)
        #expect(tile.id == november)
        #expect(tile.source == compact)
        #expect(tile.destination == expanded)
    }

    @Test func matchesBothVisibleMonthsWhenZoomingOut() throws {
        let model = CalendarZoomTransitionModel()
        let decemberDetail = expanded.offsetBy(dx: 0, dy: 376)
        let decemberOverview = compact.offsetBy(dx: 128, dy: 0)
        model.begin(
            from: .init(
                mode: .detail,
                frames: [november: expanded, december: decemberDetail],
                viewport: viewport,
                content: content,
            ),
            to: .overview,
            focus: november,
        )
        model.resolve(
            destination: .init(
                mode: .overview,
                frames: [november: compact, december: decemberOverview],
                viewport: viewport,
                content: content,
            ),
        )
        let plan = try movingPlan(model)
        #expect(plan.tiles.map(\.id) == [november, december])
        #expect(plan.tiles.map(\.source) == [expanded, decemberDetail])
        #expect(plan.tiles.map(\.destination) == [compact, decemberOverview])
        #expect(plan.tiles.allSatisfy { $0.visibility == .both })
    }

    @Test(arguments: [CalendarPresentationModel.Mode.detail, .overview])
    func projectedFramesCannotIntroduceAnOffscreenMonth(destinationMode: CalendarPresentationModel
        .Mode)
        throws
    {
        let august = CalendarPresentationModel.Target.month(CalendarDay(
            year: 2026,
            month: 8,
            day: 1,
        ))
        let overview = CalendarZoomTransitionModel.Measurement(
            mode: .overview,
            frames: [november: compact, august: compact.offsetBy(dx: 0, dy: -108)],
            viewport: viewport,
            content: content,
        )
        let detail = CalendarZoomTransitionModel.Measurement(
            mode: .detail,
            frames: [
                november: expanded.offsetBy(dx: 0, dy: 400),
                august: expanded.offsetBy(dx: 0, dy: -1500),
            ],
            viewport: viewport,
            content: content.offsetBy(dx: 0, dy: -1200),
        )
        let model = CalendarZoomTransitionModel()
        model.begin(
            from: destinationMode == .detail ? overview : detail,
            to: destinationMode,
            focus: november,
        )
        model.resolve(destination: destinationMode == .detail ? detail : overview)
        let tile = try #require(try movingPlan(model).tiles.first { $0.id == august })
        #expect(tile.source.intersects(viewport))
        #expect(tile.destination.intersects(viewport))
        #expect(tile.visibility == (destinationMode == .detail ? .source : .destination))
    }

    @Test(arguments: [false, true])
    func offscreenCounterpartsContinueTheSelectedMonthsScaleAndTranslation(
        hasOffscreenFrame: Bool,
    ) throws {
        let model = CalendarZoomTransitionModel()
        let decemberOverview = compact.offsetBy(dx: 128, dy: 0)
        model.begin(
            from: .init(
                mode: .overview,
                frames: [november: compact, december: decemberOverview],
                viewport: viewport,
                content: content,
            ),
            to: .detail,
            focus: november,
        )
        var frames = [november: expanded]
        if hasOffscreenFrame { frames[december] = expanded.offsetBy(dx: 0, dy: 2000) }
        model.resolve(
            destination: .init(mode: .detail, frames: frames, viewport: viewport, content: content),
        )
        let tile = try #require(try movingPlan(model).tiles.first { $0.id == december })
        #expect(tile.source == decemberOverview)
        #expect(abs(tile.destination.width - expanded.width) < 0.001)
        #expect(
            abs(tile.destination.midX - (expanded.midX + 128 * expanded.width / compact.width)) <
                0.001,
        )
        #expect(abs(tile.destination.midY - expanded.midY) < 0.001)
        #expect(!tile.destination.intersects(viewport))
    }

    @Test func estimateCanSettleAgainstTheBottomInsteadOfTheTop() throws {
        let model = CalendarZoomTransitionModel()
        let estimate = CalendarPresentationModel.Target.estimate(CalendarDay(
            year: 2026,
            month: 7,
            day: 1,
        ))
        let source = CGRect(x: 16, y: 550, width: 370, height: 200)
        let destination = source.offsetBy(dx: 0, dy: -50)
        model.begin(
            from: .init(
                mode: .overview,
                frames: [estimate: source],
                viewport: viewport,
                content: content,
            ),
            to: .detail,
            focus: estimate,
        )
        model.resolve(
            destination: .init(
                mode: .detail,
                frames: [estimate: destination],
                viewport: viewport,
                content: content.offsetBy(dx: 0, dy: -1200),
            ),
        )
        let tile = try #require(try movingPlan(model).tiles.first)
        #expect(tile.id == estimate)
        #expect(tile.source.size == tile.destination.size)
        #expect(tile.destination == destination)
    }

    @Test func staleCompletionCannotEndANewerTransition() throws {
        let model = CalendarZoomTransitionModel()
        let measurement = CalendarZoomTransitionModel.Measurement(
            mode: .overview,
            frames: [november: compact],
            viewport: viewport,
            content: content,
        )
        model.begin(from: measurement, to: .detail, focus: november)
        let cancelledID = try #require(model.phase?.source.id)
        model.cancel()
        model.begin(from: measurement, to: .detail, focus: november)
        let activeID = try #require(model.phase?.source.id)
        #expect(!model.finish(cancelledID))
        #expect(model.phase?.source.id == activeID)
        #expect(model.finish(activeID))
        #expect(model.phase == nil)
    }

    @Test(arguments: [false, true])
    func resizingCancelsInsteadOfAnimatingStaleCoordinates(alreadyMoving: Bool) {
        let model = CalendarZoomTransitionModel()
        model.begin(
            from: .init(
                mode: .overview,
                frames: [november: compact],
                viewport: viewport,
                content: content,
            ),
            to: .detail,
            focus: november,
        )
        if alreadyMoving {
            model.resolve(
                destination: .init(
                    mode: .detail,
                    frames: [november: expanded],
                    viewport: viewport,
                    content: content,
                ),
            )
        }
        model.resolve(
            destination: .init(
                mode: .detail,
                frames: [november: expanded],
                viewport: viewport.insetBy(dx: 10, dy: 0),
                content: content,
            ),
        )
        #expect(model.phase == nil)
    }

    @Test func disjointLazyLayoutsReleaseTheOverlay() {
        let model = CalendarZoomTransitionModel()
        model.begin(
            from: .init(
                mode: .detail,
                frames: [november: expanded],
                viewport: viewport,
                content: content,
            ),
            to: .overview,
            focus: november,
        )
        model.resolve(
            destination: .init(
                mode: .overview,
                frames: [december: compact],
                viewport: viewport,
                content: content,
            ),
        )
        #expect(model.phase == nil)
    }

    @Test func unrelatedLayoutCallbacksCannotStartTheFlight() {
        let model = CalendarZoomTransitionModel()
        let overview = CalendarZoomTransitionModel.Measurement(
            mode: .overview,
            frames: [november: compact],
            viewport: viewport,
            content: content,
        )
        model.begin(from: overview, to: .detail, focus: november)
        model.resolve(destination: overview)
        guard case .preparing = model.phase else {
            Issue.record("An outgoing layout callback must not resolve the incoming layout")
            return
        }
    }

    @Test func subpixelViewportRoundingDoesNotCancelMatching() throws {
        let model = CalendarZoomTransitionModel()
        model.begin(
            from: .init(
                mode: .overview,
                frames: [november: compact],
                viewport: viewport,
                content: content,
            ),
            to: .detail,
            focus: november,
        )
        var rounded = viewport
        rounded.size.width += 0.0000000001
        model.resolve(
            destination: .init(
                mode: .detail,
                frames: [november: expanded],
                viewport: rounded,
                content: content,
            ),
        )
        #expect(try movingPlan(model).tiles.count == 1)
    }

    @Test func waitsForIncomingMeasurementsAfterOutgoingAnchorsDisappear() {
        let model = CalendarZoomTransitionModel()
        model.begin(
            from: .init(
                mode: .detail,
                frames: [november: expanded],
                viewport: viewport,
                content: content,
            ),
            to: .overview,
            focus: november,
        )
        model.resolve(
            destination: .init(mode: .overview, frames: [:], viewport: viewport, content: content),
        )
        guard case .preparing = model.phase else {
            Issue.record("Missing incoming anchors must keep the outgoing tiles visible")
            return
        }
    }

    @Test func offscreenEstimateEntersAtFullWidthBelowTheGrid() throws {
        let model = CalendarZoomTransitionModel()
        let estimate = CalendarPresentationModel.Target.estimate(CalendarDay(
            year: 2026,
            month: 7,
            day: 1,
        ))
        let source = CGRect(x: 16, y: -1000, width: 370, height: 424)
        let destination = CGRect(x: 16, y: 550, width: 370, height: 368)
        model.begin(
            from: .init(
                mode: .detail,
                frames: [november: expanded, estimate: source],
                viewport: viewport,
                content: content,
            ),
            to: .overview,
            focus: november,
        )
        model.resolve(
            destination: .init(
                mode: .overview,
                frames: [november: compact, estimate: destination],
                viewport: viewport,
                content: content,
            ),
        )
        let tile = try #require(try movingPlan(model).tiles.first { $0.id == estimate })
        #expect(tile.source.size == source.size)
        #expect(tile.source.minY == viewport.maxY)
        #expect(tile.destination == destination)
    }

    private func movingPlan(_ model: CalendarZoomTransitionModel) throws
        -> CalendarZoomTransitionModel.Plan
    {
        try #require({ () -> CalendarZoomTransitionModel.Plan? in
            guard case let .moving(plan) = model.phase else { return nil }
            return plan
        }())
    }
}
