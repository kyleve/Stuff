import SFSafeSymbols
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
        let image = try await renderSnapshotImage(
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
        let image = try await renderSnapshotImage(
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
        let image = try await renderSnapshotImage(
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

    @Test(arguments: [false, true])
    func restoredScrollOffsetsApplyOnlyToViewportCaptures(fullContent: Bool) async throws {
        try waitFor { hostKeyWindow() != nil }
        let host = UIHostingController(rootView: ScrollView {
            VStack(spacing: 0) {
                Color.red.frame(height: 100)
                Color.blue.frame(height: 2900)
            }
        })
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let image = try await renderSnapshotImage(
            of: host,
            named: "restored-scroll-offset",
            sizing: fullContent ? .intrinsic(width: 402, minimumHeight: 874) : .fixed,
            safeAreaInsets: .zero,
            onReadyToSnapshot: {
                @MainActor func scrollViews(in view: UIView) -> [UIScrollView] {
                    if let scrollView = view as? UIScrollView { return [scrollView] }
                    return view.subviews.flatMap { scrollViews(in: $0) }
                }
                guard let scrollView = scrollViews(in: host.view).first else {
                    Issue.record("The hosted fixture must contain its production scroll view")
                    return
                }
                scrollView.setContentOffset(CGPoint(x: 0, y: 180), animated: false)
            },
        )
        let firstRow = image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.01))
        if fullContent {
            #expect(image.size.height == 3000)
            #expect(firstRow.red > 0.5)
            #expect(firstRow.blue < 0.5)
            #expect(image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.99)).blue > 0.5)
        } else {
            #expect(image.size.height == 874)
            #expect(firstRow.blue > 0.5)
            #expect(firstRow.red < 0.5)
        }
    }

    @Test func capturesAHorizontalScrollViewsFullContentInMultipleTiles() async throws {
        try waitFor { hostKeyWindow() != nil }
        let scroll = ScrollView(.horizontal) {
            HStack(spacing: 0) {
                Color.red.frame(width: 1500)
                Color.blue.frame(width: 1500)
            }
        }
        let host = UIHostingController(rootView: scroll)
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 600)
        let image = try await renderSnapshotImage(
            of: host,
            named: "two-axis-horizontal-scroll-probe",
            sizing: .fullContent2D(minimumSize: CGSize(width: 402, height: 600)),
            safeAreaInsets: .zero,
        )

        #expect(image.size == CGSize(width: 3000, height: 600))
        #expect(image.probePixel(atUnitPoint: CGPoint(x: 0.1, y: 0.5)).red > 0.5)
        #expect(image.probePixel(atUnitPoint: CGPoint(x: 0.9, y: 0.5)).blue > 0.5)
    }

    @Test func capturesASpatialScrollViewsFullContentAlongBothAxes() async throws {
        try waitFor { hostKeyWindow() != nil }
        let canvas = ScrollView([.horizontal, .vertical]) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    Color.red
                    Color.green
                }
                GridRow {
                    Color.blue
                    Color.yellow
                }
            }
            .frame(width: 2400, height: 2200)
        }
        let host = UIHostingController(rootView: canvas)
        host.view.frame = CGRect(x: 0, y: 0, width: 834, height: 1194)
        let image = try await renderSnapshotImage(
            of: host,
            named: "two-axis-spatial-scroll-probe",
            sizing: .fullContent2D(minimumSize: CGSize(width: 834, height: 1194)),
            safeAreaInsets: .zero,
        )

        #expect(image.size == CGSize(width: 2400, height: 2200))
        #expect(image.probePixel(atUnitPoint: CGPoint(x: 0.1, y: 0.1)).red > 0.5)
        #expect(image.probePixel(atUnitPoint: CGPoint(x: 0.9, y: 0.1)).green > 0.5)
        #expect(image.probePixel(atUnitPoint: CGPoint(x: 0.1, y: 0.9)).blue > 0.5)
        let bottomTrailing = image.probePixel(atUnitPoint: CGPoint(x: 0.9, y: 0.9))
        #expect(bottomTrailing.red > 0.5)
        #expect(bottomTrailing.green > 0.5)
    }

    @Test func rejectsUnsafeTwoAxisPixelAllocations() async throws {
        try waitFor { hostKeyWindow() != nil }
        let scale = try #require(hostKeyWindow()).screen.scale
        let canvas = ScrollView([.horizontal, .vertical]) {
            Color.red.frame(width: 20000, height: 20000)
        }
        let host = UIHostingController(rootView: canvas)
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)

        do {
            _ = try await renderSnapshotImage(
                of: host,
                named: "unsafe-two-axis-allocation-probe",
                sizing: .fullContent2D(minimumSize: CGSize(width: 402, height: 874)),
                safeAreaInsets: .zero,
            )
            Issue.record("Expected unsafe two-axis allocation to fail.")
        } catch let error as SnapshotRenderingError {
            guard case let .fullContentSizeExceedsLimit(
                name,
                pixelWidth,
                pixelHeight,
                maximumPixelDimension,
                maximumPixelCount,
            ) = error else {
                Issue.record("Expected allocation limit failure, got \(error).")
                return
            }
            #expect(name == "unsafe-two-axis-allocation-probe")
            #expect(pixelWidth == Int(20000 * scale))
            #expect(pixelHeight == Int(20000 * scale))
            #expect(maximumPixelDimension == 32000)
            #expect(maximumPixelCount == 100_000_000)
        } catch {
            Issue.record("Expected SnapshotRenderingError, got \(error).")
        }
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
                Color.green
                    .frame(height: 50)
                    .accessibilityLabel("Bottom toolbar")
            }
            .navigationTitle("Full Content")
            .toolbarBackground(Color.yellow, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemSymbol: .plus, action: {})
                }
            }
        }
        let host = UIHostingController(rootView: screen)
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 1)
        let image = try await renderSnapshotImage(
            of: host,
            named: "full-content-navigation-probe",
            sizing: .intrinsic(width: 402, minimumHeight: 0),
            safeAreaInsets: .zero,
            measurementReadiness: .immediate,
        )
        // Native bar heights vary by runtime and arrangement. Prove that all
        // 3,000 points of content survive, independently of that chrome height.
        var redRows = 0
        var blueRows = 0
        var greenRows = 0
        for row in 0 ..< Int(image.size.height) {
            let pixel = image.probePixel(atUnitPoint: CGPoint(
                x: 0.5,
                y: (CGFloat(row) + 0.5) / image.size.height,
            ))
            if pixel.red > 0.5, pixel.green < 0.5, pixel.blue < 0.5 { redRows += 1 }
            if pixel.blue > 0.5, pixel.red < 0.5 { blueRows += 1 }
            if pixel.green > 0.5, pixel.red < 0.5, pixel.blue < 0.5 { greenRows += 1 }
        }
        #expect(abs(redRows - 1500) <= 1)
        #expect(abs(blueRows - 1500) <= 1)
        #expect(abs(greenRows - 50) <= 1)

        let topToolbar = image.probePixel(atUnitPoint: CGPoint(
            x: 0.1,
            y: 20 / image.size.height,
        ))
        #expect(topToolbar.red > 0.5)
        #expect(topToolbar.green > 0.5)
        #expect(topToolbar.blue < 0.5)

        let firstContent = image.probePixel(atUnitPoint: CGPoint(
            x: 0.5,
            y: 200 / image.size.height,
        ))
        #expect(firstContent.red > 0.5)
        #expect(firstContent.blue < 0.5)

        let lastContent = image.probePixel(atUnitPoint: CGPoint(
            x: 0.5,
            y: (image.size.height - 160) / image.size.height,
        ))
        #expect(lastContent.blue > 0.5)
        #expect(lastContent.red < 0.5)

        let bottomToolbar = image.probePixel(atUnitPoint: CGPoint(
            x: 0.5,
            y: (image.size.height - 80) / image.size.height,
        ))
        #expect(bottomToolbar.green > 0.5)
        #expect(bottomToolbar.red < 0.5)
    }

    @Test func rejectsNonConvergingBoundedScrollMeasurement() async throws {
        try waitFor { hostKeyWindow() != nil }
        let screen = VStack(spacing: 0) {
            Color.red.frame(height: 100)
            List(0 ..< 20, id: \.self) { index in
                Text("Bounded row \(index)")
            }
            .frame(height: 200)
        }
        let host = UIHostingController(rootView: screen)
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 1)

        do {
            _ = try await renderSnapshotImage(
                of: host,
                named: "non-converging-bounded-scroll-probe",
                sizing: .intrinsic(width: 402, minimumHeight: 0),
                safeAreaInsets: .zero,
            )
            Issue.record("Expected intrinsic-height measurement to fail.")
        } catch let error as SnapshotRenderingError {
            guard case let .intrinsicHeightDidNotConverge(name, measuredHeights) = error else {
                Issue.record("Expected non-convergence, got \(error).")
                return
            }
            #expect(name == "non-converging-bounded-scroll-probe")
            #expect(measuredHeights.count == 11)
            #expect((measuredHeights.last ?? 0) > (measuredHeights.first ?? 0))
        } catch {
            Issue.record("Expected SnapshotRenderingError, got \(error).")
        }
    }

    @Test func searchableFullContentUsesTheCaptureWindowAndRetainsEveryRow() async throws {
        try waitFor { hostKeyWindow() != nil }
        let screen = NavigationStack {
            List {
                ForEach(0 ..< 20, id: \.self) { _ in
                    Color.red.frame(height: 100).listRowInsets(EdgeInsets())
                }
                Color.blue.frame(height: 500).listRowInsets(EdgeInsets())
            }
            .searchable(text: .constant(""))
            .navigationTitle("Searchable history")
        }
        let host = UIHostingController(rootView: screen)
        host.traitOverrides.horizontalSizeClass = .compact
        host.traitOverrides.verticalSizeClass = .regular
        host.traitOverrides.userInterfaceIdiom = .phone
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 1)
        let image = try await renderSnapshotImage(
            of: host,
            named: "searchable-full-content-probe",
            sizing: .intrinsic(width: 402, minimumHeight: 874),
            safeAreaInsets: .zero,
            onReadyToSnapshot: {
                #expect(host.view.window?.bounds.size == host.view.bounds.size)
                @MainActor func searchBars(in view: UIView) -> [UITextField] {
                    if let field = view as? UITextField { return [field] }
                    return view.subviews.flatMap { searchBars(in: $0) }
                }
                let bars = searchBars(in: host.view)
                #expect(!bars.isEmpty)
                for bar in bars {
                    let frame = bar.convert(bar.bounds, to: host.view)
                    #expect(frame.maxY <= host.view.bounds.maxY)
                    #expect(frame.maxY >= host.view.bounds.maxY - 120)
                }
            },
        )
        var redRows = 0
        var blueRows = 0
        for row in 0 ..< Int(image.size.height) {
            let pixel = image.probePixel(atUnitPoint: CGPoint(
                x: 0.5,
                y: (CGFloat(row) + 0.5) / image.size.height,
            ))
            if pixel.red > 0.5, pixel.green < 0.5, pixel.blue < 0.5 { redRows += 1 }
            if pixel.blue > 0.5, pixel.red < 0.5 { blueRows += 1 }
        }
        #expect(image.size.height >= 2500)
        #expect(redRows >= 1980)
        #expect(blueRows >= 490)
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
        let image = try await renderSnapshotImage(
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
        let image = try await renderSnapshotImage(
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
