#if DEBUG
    import CoreGraphics
    @testable import Flyover
    import Foundation
    import ImageIO
    import Testing

    struct FlyoverWebThumbnailTests {
        @Test func cropsFullContentToItsTopViewport() async throws {
            let source = try makePNG(
                width: 2,
                height: 4,
                rowColors: [
                    RGBA(red: 255, green: 0, blue: 0, alpha: 255),
                    RGBA(red: 0, green: 255, blue: 0, alpha: 255),
                    RGBA(red: 0, green: 0, blue: 255, alpha: 255),
                    RGBA(red: 255, green: 255, blue: 0, alpha: 255),
                ],
            )

            let thumbnail = try await FlyoverWebThumbnail.make(
                from: source,
                pointSize: CGSize(width: 2, height: 4),
                viewportPointSize: CGSize(width: 2, height: 2),
            )

            #expect(thumbnail.pixelSize == CGSize(width: 2, height: 2))
            let image = try decode(thumbnail.pngData)
            #expect(try pixel(in: image, x: 0, y: 0) == [255, 0, 0, 255])
            #expect(try pixel(in: image, x: 0, y: 1) == [0, 255, 0, 255])
        }

        @Test func capsTheLongestPixelDimension() async throws {
            let source = try makePNG(
                width: FlyoverWebThumbnail.maximumPixelDimension + 1,
                height: 1,
                rowColors: [RGBA(red: 42, green: 84, blue: 126, alpha: 255)],
            )

            let thumbnail = try await FlyoverWebThumbnail.make(
                from: source,
                pointSize: CGSize(
                    width: FlyoverWebThumbnail.maximumPixelDimension + 1,
                    height: 1,
                ),
                viewportPointSize: nil,
            )

            #expect(thumbnail.pixelSize.width == CGFloat(FlyoverWebThumbnail.maximumPixelDimension))
            #expect(thumbnail.pixelSize.height == 1)
        }

        @Test func rejectsInvalidPNGData() async {
            await #expect(throws: FlyoverWebThumbnailError.invalidPNG) {
                try await FlyoverWebThumbnail.make(
                    from: Data("not a png".utf8),
                    pointSize: CGSize(width: 1, height: 1),
                    viewportPointSize: nil,
                )
            }
        }

        private func makePNG(
            width: Int,
            height: Int,
            rowColors: [RGBA],
        ) throws -> Data {
            let colors = rowColors.count == 1
                ? Array(repeating: rowColors[0], count: height)
                : rowColors
            #expect(colors.count == height)
            var bytes: [UInt8] = []
            bytes.reserveCapacity(width * height * 4)
            for color in colors {
                for _ in 0 ..< width {
                    bytes.append(contentsOf: [color.red, color.green, color.blue, color.alpha])
                }
            }
            let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
            let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let image = try #require(CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent,
            ))
            let output = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(
                output,
                "public.png" as CFString,
                1,
                nil,
            ))
            CGImageDestinationAddImage(destination, image, nil)
            try #require(CGImageDestinationFinalize(destination))
            return output as Data
        }

        private func decode(_ data: Data) throws -> CGImage {
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        }

        private func pixel(in image: CGImage, x: Int, y: Int) throws -> [UInt8] {
            let provider = try #require(image.dataProvider)
            let data = try #require(provider.data)
            let bytes = CFDataGetBytePtr(data)
            let offset = y * image.bytesPerRow + x * 4
            return (0 ..< 4).map { bytes?[offset + $0] ?? 0 }
        }

        private struct RGBA {
            let red: UInt8
            let green: UInt8
            let blue: UInt8
            let alpha: UInt8
        }
    }
#endif
