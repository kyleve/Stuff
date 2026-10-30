import SwiftUI
import Testing
import ViewDocumentCore
@testable import ViewDocumentUI

@MainActor
struct ViewDocumentImageTests {
    @Test(arguments: [ViewImageDescriptor.Sizing.fit, .fill, .tile(scale: 0.5)])
    func imageSizingPreservesHostBounds(sizing: ViewImageDescriptor.Sizing) throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        let renderer = ImageRenderer(content: ViewDocumentImage(
            image: Image(uiImage: source),
            sizing: sizing,
        )
        .frame(width: 80, height: 80))
        let image = try #require(renderer.uiImage)
        #expect(image.size == CGSize(width: 80, height: 80))
    }

    @Test func imageModesHaveDistinctPixelsAndFillStaysClipped() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: format)
            .image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
                UIColor.blue.setFill()
                context.fill(CGRect(x: 20, y: 0, width: 20, height: 20))
            }
        func pixels(_ sizing: ViewImageDescriptor.Sizing) throws -> [UInt8] {
            let view = ViewDocumentImage(image: Image(uiImage: source), sizing: sizing)
                .frame(width: 80, height: 80).padding(10)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            var bytes = [UInt8](repeating: 0, count: 100 * 100 * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try #require(CGContext(
                    data: buffer.baseAddress,
                    width: 100,
                    height: 100,
                    bitsPerComponent: 8,
                    bytesPerRow: 400,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
                ))
                context.draw(image, in: CGRect(x: 0, y: 0, width: 100, height: 100))
            }
            return bytes
        }
        let fit = try pixels(.fit)
        let fill = try pixels(.fill)
        let tile = try pixels(.tile(scale: 1))
        func channel(_ pixels: [UInt8], x: Int, y: Int, channel: Int) -> UInt8 {
            pixels[(y * 100 + x) * 4 + channel]
        }
        // Top inset inside the host: fit is transparent, fill occupies the full height.
        #expect(channel(fit, x: 20, y: 20, channel: 3) == 0)
        #expect(channel(fill, x: 20, y: 20, channel: 3) == 255)
        // The second tile starts red again; the cropped fill remains blue on the right.
        #expect(channel(tile, x: 60, y: 50, channel: 0) == 255)
        #expect(channel(fill, x: 60, y: 50, channel: 2) == 255)
        // Cropped source pixels never escape into the surrounding padding.
        #expect(channel(fill, x: 5, y: 50, channel: 3) == 0)
        #expect(channel(fill, x: 95, y: 50, channel: 3) == 0)
    }
}
