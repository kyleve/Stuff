@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

/// Regression guard for the tile-and-stitch capture path. UIKit renders a blank
/// image for views taller/wider than ~2000pt (verified reproducing on this
/// toolchain), so the pipeline captures oversized views in tiles. A short view
/// (single tile) and a very tall view (multiple tiles) must both come out whole.
///
/// Also guards the full-content scroll capture (`Frame.fullContent`): a
/// `ScrollView` measured under the pipeline's unbounded `sizeThatFits` proposal
/// must report its *content* height (verified on this toolchain — no
/// `.fixedSize` shim is needed), so the whole scrollable content renders with
/// nothing scrolled out of frame. UIKit-backed SwiftUI containers such as
/// `Form` need the pipeline's root-scroll fallback because they report only
/// their viewport through `sizeThatFits`.
@MainActor
struct LargeViewCaptureTests {
    @Test func capturesAShortViewInOneTile() async throws {
        let sample = try await renderTwoTone(height: 800)
        #expect(sample.size.height == 800)
        #expect(sample.top.red > 0.5)
        #expect(sample.bottom.blue > 0.5)
    }

    @Test func contentMeasuredSizingRetainsItsMinimumHeight() async throws {
        try waitFor { hostKeyWindow() != nil }
        let view = Color.red.frame(width: 402, height: 100)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 1)
        let image = await renderSnapshotImage(
            of: host,
            named: "full-content-minimum-height-probe",
            sizing: .intrinsic(width: 402, minimumHeight: 874),
            safeAreaInsets: .zero,
        )
        #expect(image.size.height == 874)
    }

    @Test func capturesAViewTallerThanTheTileLimit() async throws {
        let sample = try await renderTwoTone(height: 3000)
        #expect(sample.size.height == 3000)
        #expect(sample.top.red > 0.5)
        #expect(sample.bottom.blue > 0.5)
    }

    /// The `Frame.fullContent` mechanism: a >2000pt `ScrollView` captured via
    /// the content-measured (`.intrinsic`) sizing it maps onto comes out whole
    /// — full content height, both colors present at the extremes.
    @Test func capturesAScrollViewsFullContentUnderContentMeasuredSizing() async throws {
        try waitFor { hostKeyWindow() != nil }
        let scroll = ScrollView {
            VStack(spacing: 0) {
                Color.red.frame(height: 1500)
                Color.blue.frame(height: 1500)
            }
        }
        let host = UIHostingController(rootView: scroll)
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 1)
        let image = await renderSnapshotImage(
            of: host,
            named: "full-content-scroll-probe",
            sizing: .intrinsic(width: 402, minimumHeight: 0),
            safeAreaInsets: .zero,
        )
        let sample = TwoToneSample(
            top: image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.1)),
            bottom: image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.9)),
            size: image.size,
        )
        #expect(sample.size.height == 3000)
        #expect(sample.top.red > 0.5)
        #expect(sample.bottom.blue > 0.5)
    }

    @Test func capturesAFormsFullContentUnderContentMeasuredSizing() async throws {
        try waitFor { hostKeyWindow() != nil }
        let form = Form {
            Section {
                ForEach(0 ..< 20, id: \.self) { _ in
                    Color.red
                        .frame(height: 80)
                        .listRowInsets(EdgeInsets())
                }
                Color.blue
                    .frame(height: 500)
                    .listRowInsets(EdgeInsets())
            }
        }
        let host = UIHostingController(rootView: form)
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 1)
        let image = await renderSnapshotImage(
            of: host,
            named: "full-content-form-probe",
            sizing: .intrinsic(width: 402, minimumHeight: 0),
            safeAreaInsets: .zero,
        )
        let sample = TwoToneSample(
            top: image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.1)),
            bottom: image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.9)),
            size: image.size,
        )
        #expect(sample.size.height > 2000)
        #expect(sample.top.red > 0.5)
        #expect(sample.bottom.blue > 0.5)
    }

    @Test func preservesChromeAroundFullContentScrollingContent() async throws {
        try waitFor { hostKeyWindow() != nil }
        let screen = NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Color.red.frame(height: 1500)
                    Color.blue.frame(height: 1500)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Bottom toolbar")
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(.regularMaterial)
            }
            .navigationTitle("Full Content")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus", action: {})
                }
            }
        }
        let host = UIHostingController(rootView: screen)
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 1)
        let image = await renderSnapshotImage(
            of: host,
            named: "full-content-navigation-probe",
            sizing: .intrinsic(width: 402, minimumHeight: 0),
            safeAreaInsets: .zero,
        )
        #expect(image.size.height >= 3050)
    }

    @Test func annotatesTallFullContentAccessibilitySnapshots() async throws {
        try waitFor { hostKeyWindow() != nil }
        let screen = ScrollView {
            VStack {
                ForEach(0 ..< 30, id: \.self) { index in
                    Text("Accessible row \(index)")
                        .frame(maxWidth: .infinity, minHeight: 100)
                }
            }
        }
        let host = UIHostingController(rootView: screen)
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 1)
        let image = await renderSnapshotImage(
            of: host,
            named: "full-content-accessibility-probe",
            sizing: .intrinsic(width: 402, minimumHeight: 0),
            safeAreaInsets: .zero,
            isAccessibility: true,
        )
        #expect(image.size.height > 3000)
        #expect(image.size.width > 402)
    }

    private func renderTwoTone(height: CGFloat) async throws -> TwoToneSample {
        try waitFor { hostKeyWindow() != nil }
        let half = height / 2
        let view = VStack(spacing: 0) {
            Color.red.frame(height: half)
            Color.blue.frame(height: half)
        }
        .frame(width: 402, height: height)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: height)
        let image = await renderSnapshotImage(
            of: host,
            named: "two-tone-\(Int(height))pt-probe",
            safeAreaInsets: .zero,
        )
        return TwoToneSample(
            top: image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.1)),
            bottom: image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.9)),
            size: image.size,
        )
    }
}

private struct TwoToneSample {
    let top: PixelSample
    let bottom: PixelSample
    let size: CGSize
}
