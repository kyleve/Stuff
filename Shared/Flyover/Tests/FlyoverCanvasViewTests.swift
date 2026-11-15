@_spi(Testing) @testable import Flyover
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct FlyoverCanvasViewTests {
    @Test func movingViewportDefersNewPreviewTreesUntilItSettles() async throws {
        var builds: [Int] = []
        let screens = (0 ..< 20).map { screenID in
            FlyoverScreen(
                id: screenID,
                title: "Screen \(screenID)",
                position: FlyoverPosition(column: screenID, row: 0),
                variants: [
                    FlyoverVariant(id: FlyoverVariantID("default"), title: "Default") {
                        builds.append(screenID)
                        return List {
                            Text("Preview \(screenID)")
                        }
                        .navigationTitle("Screen \(screenID)")
                    },
                ],
            )
        }
        let catalog = FlyoverCatalog(groups: [
            FlyoverGroup(
                id: FlyoverGroupID("stress"),
                title: "Stress",
                root: 0,
                screens: screens,
            ),
        ])
        let model = FlyoverModel(catalog: catalog)
        let settling = FlyoverSettlingGate()
        model.setCanvasSettlingOperation { await settling.wait() }
        defer { settling.release() }
        model.applyInitialCanvasZoom(0.45)
        let host = UIHostingController(rootView: FlyoverView(catalog: catalog, model: model))
        try await show(host) { host in
            try await waitForFlyover { model.previewReadiness.isReadyForLatestExpectation }
            let initialBuildCount = builds.count
            #expect(initialBuildCount > 0)
            let scrollView = try #require(canvasScrollView(in: host.view))

            settling.isHeld = true
            // Space gesture inputs across display frames. Completion and no-build
            // assertions use the held settling boundary, never this input cadence.
            for step in 1 ... 20 {
                scrollView.setContentOffset(CGPoint(x: step * 100, y: 0), animated: false)
                try await Task.sleep(for: .milliseconds(30))
                #expect(builds.count == initialBuildCount)
            }
            try await waitForFlyover {
                model.previewReadiness.expectedKeys?.contains { $0.screenID > 10 } == true
            }

            settling.release()
            try await waitForFlyover { builds.count > initialBuildCount }
            try await waitForFlyover { model.previewReadiness.isReadyForLatestExpectation }
            #expect(builds.count <= initialBuildCount + 6)
            #expect(builds.contains { $0 > 10 })

            // Returning to an earlier viewport must be able to load again.
            let beforeReturn = builds.count
            scrollView.setContentOffset(.zero, animated: false)
            try await waitForFlyover { builds.count > beforeReturn }
            try await waitForFlyover { model.previewReadiness.isReadyForLatestExpectation }
            #expect(builds.count(where: { $0 == 0 }) == 2)

            // Retaining one loaded neighbor must not satisfy snapshot readiness
            // while a newly visible neighbor is waiting for the viewport to settle.
            settling.isHeld = true
            scrollView.setContentOffset(CGPoint(x: 180, y: 0), animated: false)
            try await waitForFlyover {
                model.previewReadiness.expectedKeys?.contains { $0.screenID == 2 } == true
            }
            #expect(model.previewReadiness.isReadyForLatestExpectation == false)
            settling.release()
            try await waitForFlyover { model.previewReadiness.isReadyForLatestExpectation }

            settling.isHeld = true
            let beforeZoom = builds.count
            for step in 0 ..< 21 {
                model.zoom = step.isMultiple(of: 2) ? 0.15 : 0.45
                try await Task.sleep(for: .milliseconds(30))
                #expect(builds.count == beforeZoom)
            }
            try await waitForFlyover {
                (model.previewReadiness.expectedKeys?.count ?? 0) > 3
            }
            settling.release()
            try await waitForFlyover { builds.count > beforeZoom }
            try await waitForFlyover { model.previewReadiness.isReadyForLatestExpectation }
            #expect(builds.count <= beforeZoom + 6)
        }
    }

    private func canvasScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView, scrollView.contentSize.width > 2000 {
            return scrollView
        }
        return view.subviews.lazy.compactMap { canvasScrollView(in: $0) }.first
    }
}
