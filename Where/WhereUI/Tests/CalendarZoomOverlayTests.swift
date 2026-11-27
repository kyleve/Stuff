import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct CalendarZoomOverlayTests {
    @Test(.serialized, arguments: [false, true])
    func mountsEachEndpointOnce(destinationAlreadyReady: Bool) async throws {
        let zoom = CalendarZoomTransitionState()
        let month = CalendarPresentationState.Target.month(CalendarDay(
            year: 2026,
            month: 11,
            day: 1,
        ))
        let viewport = CGRect(x: 0, y: 0, width: 402, height: 800)
        zoom.begin(
            from: .init(
                mode: .overview,
                frames: [month: CGRect(x: 100, y: 0, width: 120, height: 100)],
                viewport: viewport,
                content: viewport,
            ),
            to: .detail,
            focus: month,
        )
        let source = try #require(zoom.phase)
        var mounts: [CalendarPresentationState.Mode: Int] = [:]
        var finished: CalendarZoomTransitionState.ID?
        @ViewBuilder func overlay(_ phase: CalendarZoomTransitionState.Phase?) -> some View {
            if let phase {
                CalendarZoomOverlay(phase: phase) { _, mode in
                    Color.blue.onAppear { mounts[mode, default: 0] += 1 }
                } completion: { finished = $0 }
                    .transaction { $0.animation = nil }
            }
        }

        func measuredDestination() throws -> CalendarZoomTransitionState.Phase {
            zoom.updateMeasurement(.init(
                mode: .detail,
                frames: [month: CGRect(x: 16, y: 0, width: 370, height: 360)],
                viewport: viewport,
                content: viewport,
            ))
            return try #require(zoom.phase)
        }

        let initialPhase = try destinationAlreadyReady ? measuredDestination() : source
        let host = UIHostingController(rootView: overlay(nil))
        try await show(host) { host in
            host.view.window?.layer.speed = 1
            host.rootView = overlay(initialPhase)
            if !destinationAlreadyReady {
                try await waitForAsync { mounts[.overview] == 1 }
                host.rootView = try overlay(measuredDestination())
            }
            try await waitForAsync { finished == source.source.id }
            #expect(mounts == [.overview: 1, .detail: 1])
        }
    }
}
