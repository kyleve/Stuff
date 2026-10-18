@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import Testing

@MainActor
struct SnapshotWebPageTests {
    @Test func capturesSharpContentAtDocumentEdges() async throws {
        let image = try await loadHTMLSnapshotImage(
            """
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>body {margin:0;height:240px;
            background:repeating-linear-gradient(90deg,#000 0 8px,#fff 8px 16px)}</style>
            """,
            configuration: .init(device: .fullContent(
                name: "web-edges",
                width: 120,
                minimumHeight: 80,
            )),
        )
        for y in [24.0, image.size.height - 24] {
            let black = image.probePixel(atUnitPoint: CGPoint(
                x: 52 / 120.0,
                y: y / image.size.height,
            ))
            let white = image.probePixel(atUnitPoint: CGPoint(
                x: 60 / 120.0,
                y: y / image.size.height,
            ))
            #expect(black.red < 0.1)
            #expect(white.red > 0.9)
        }
    }

    @Test func capturesLoadedFullDocumentIncludingPixelsBelowTheViewport() async throws {
        let configuration = SnapshotConfiguration(
            device: .fullContent(name: "web-probe", width: 120, minimumHeight: 60),
        )
        let image = try await loadHTMLSnapshotImage(
            """
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>body {margin:0} header {height:80px;background:#ff0000}
            footer {height:2450px;background:#0000ff}</style><header></header><footer></footer>
            """,
            configuration: configuration,
        )
        #expect(image.size.width == 120)
        #expect(image.size.height == 2530)
        let png = try await captureSnapshotPNG(
            of: Image(uiImage: image),
            configuration: configuration,
            named: "full-html-probe",
            sizing: .intrinsic(width: 120, minimumHeight: 60),
            safeAreaInsets: .zero,
            measurementReadiness: .immediate,
            onReadyToMeasure: nil,
            settle: .settled,
            onReadyToSnapshot: nil,
        )
        #expect(png.pointSize == image.size)
        let normalizedImage = try #require(UIImage(data: png.data, scale: png.scale))
        let first = normalizedImage.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.01))
        let last = normalizedImage.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.99))
        #expect(first.red > 0.9 && first.blue < 0.1)
        #expect(last.blue > 0.9 && last.red < 0.1)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func appliesAppearanceToCSS(scheme: ColorScheme) async throws {
        let image = try await loadHTMLSnapshotImage(
            """
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>:root {color-scheme:light dark} body {margin:0;
            background:light-dark(#ffffff,#000000)}</style>
            """,
            configuration: .init(
                colorScheme: scheme,
                device: .fullContent(name: "web-theme", width: 120, minimumHeight: 80),
            ),
        )
        let pixel = image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5))
        #expect(scheme == .light ? pixel.red > 0.9 : pixel.red < 0.1)
    }

    @Test func rejectsUnsafeContentSizes() async {
        for size in [CGSize(width: 0, height: 80), CGSize(width: 120, height: CGFloat.infinity)] {
            await #expect(throws: (any Error).self) {
                try await loadHTMLSnapshotImage(
                    "<p>Fixture</p>",
                    configuration: .init(device: .fullContent(
                        name: "invalid-web-size",
                        width: size.width,
                        minimumHeight: size.height,
                    )),
                )
            }
        }
    }
}
