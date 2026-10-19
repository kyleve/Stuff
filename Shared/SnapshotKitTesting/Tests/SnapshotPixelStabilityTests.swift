@_spi(Testing) import SnapshotKitTesting
import Testing
import UIKit

struct SnapshotPixelStabilityTests {
    @Test(arguments: 0 ..< 4, -2 ... 2)
    func boundsEveryChannelToOneUnit(channel: Int, delta: Int) throws {
        let pixels: [UInt8] = [64, 64, 64, 200]
        var changed = pixels
        changed[channel] = UInt8(Int(pixels[channel]) + delta)
        let anchor = try settleTestImage(pixels)
        let sample = try settleTestImage(changed)
        var stability = SnapshotPixelStability()

        #expect(stability.observe(anchor, at: .zero) == false)
        #expect(stability.observe(sample, at: .milliseconds(64)) == false)
        #expect(stability.observe(sample, at: .milliseconds(120)) == (abs(delta) <= 1))
        #expect(stability.observedChange == (abs(delta) > 1))
    }

    @Test(arguments: [UInt8(0), 254])
    func acceptsNoiseAtChannelExtremes(value: UInt8) throws {
        let anchor = try settleTestImage([value, value, value, 255])
        let changed = try settleTestImage([value + 1, value + 1, value + 1, 255])
        var stability = SnapshotPixelStability()

        #expect(stability.observe(anchor, at: .zero) == false)
        #expect(stability.observe(changed, at: .milliseconds(64)) == false)
        let settled = stability.observe(anchor, at: .milliseconds(120))
        #expect(settled)
        #expect(stability.observedChange == false)
    }

    @Test func requiresTwoMatchesAndTheCompleteQuietWindow() throws {
        let image = try settleTestImage([200, 200, 200, 255])
        var stability = SnapshotPixelStability()

        #expect(stability.observe(image, at: .zero) == false)
        #expect(stability.observe(image, at: .milliseconds(16)) == false)
        #expect(stability.observe(image, at: .milliseconds(119)) == false)
        let settled = stability.observe(image, at: .milliseconds(120))
        #expect(settled)

        var sparse = SnapshotPixelStability()
        #expect(sparse.observe(image, at: .zero) == false)
        #expect(sparse.observe(image, at: .seconds(1)) == false)
        let sparseSettled = sparse.observe(image, at: .seconds(2))
        #expect(sparseSettled)
    }

    @Test func cumulativeOneUnitStepsResetTheFixedAnchor() throws {
        var stability = SnapshotPixelStability()
        // A one-unit step every 64 ms never exceeds the allowance between
        // adjacent frames, but reaches two units before each quiet window ends.
        for milliseconds in stride(from: 0, through: 1392, by: 16) {
            let gray = UInt8(200 + min(milliseconds / 64, 20))
            let image = try settleTestImage([gray, gray, gray, 255])
            #expect(stability.observe(image, at: .milliseconds(milliseconds)) == false)
        }
        let final = try settleTestImage([220, 220, 220, 255])
        let settled = stability.observe(final, at: .milliseconds(1408))
        #expect(settled)
        #expect(stability.observedChange)
    }

    @Test func alternatingNoiseStaysRelativeToTheAnchor() throws {
        var stability = SnapshotPixelStability()
        let anchor = try settleTestImage([200, 200, 200, 255])
        let lower = try settleTestImage([199, 199, 199, 255])
        let upper = try settleTestImage([201, 201, 201, 255])

        #expect(stability.observe(anchor, at: .zero) == false)
        #expect(stability.observe(lower, at: .milliseconds(64)) == false)
        let settled = stability.observe(upper, at: .milliseconds(128))
        #expect(settled)
        #expect(stability.observedChange == false)
    }

    @Test func oneHighContrastPixelHasNoAreaExemption() throws {
        // A change at the far end also guards against comparing an NSData hash
        // or a buffer prefix instead of every pixel.
        let pixel: [UInt8] = [200, 200, 200, 255]
        var pixels = Array(repeating: pixel, count: 101 * 518).flatMap(\.self)
        let anchor = try settleTestImage(pixels, width: 101, height: 518)
        pixels[pixels.count - 4] = 0
        let changed = try settleTestImage(pixels, width: 101, height: 518)
        var stability = SnapshotPixelStability()

        #expect(stability.observe(anchor, at: .zero) == false)
        #expect(stability.observe(changed, at: .milliseconds(64)) == false)
        #expect(stability.observe(anchor, at: .milliseconds(128)) == false)
        #expect(stability.observedChange)
    }

    @Test func missingSamplesNeverProveStability() {
        var stability = SnapshotPixelStability()
        for milliseconds in [0, 64, 128, 256] {
            #expect(stability.observe(nil, at: .milliseconds(milliseconds)) == false)
        }
        #expect(stability.observedChange == false)
    }

    @Test func missingSampleRestartsTheQuietWindow() throws {
        let image = try settleTestImage([200, 200, 200, 255])
        var stability = SnapshotPixelStability()

        #expect(stability.observe(image, at: .zero) == false)
        #expect(stability.observe(image, at: .milliseconds(64)) == false)
        #expect(stability.observe(nil, at: .milliseconds(120)) == false)
        #expect(stability.observe(image, at: .milliseconds(128)) == false)
        #expect(stability.observe(image, at: .milliseconds(192)) == false)
        let settled = stability.observe(image, at: .milliseconds(248))
        #expect(settled)
        #expect(stability.observedChange)
    }

    @Test func changedDimensionsResetTheWindowEvenWithIdenticalBytes() throws {
        let pixels: [UInt8] = [200, 200, 200, 255, 200, 200, 200, 255]
        let wide = try settleTestImage(pixels, width: 2)
        let tall = try settleTestImage(pixels, height: 2)
        var stability = SnapshotPixelStability()

        #expect(stability.observe(wide, at: .zero) == false)
        #expect(stability.observe(wide, at: .milliseconds(64)) == false)
        #expect(stability.observe(tall, at: .milliseconds(128)) == false)
        #expect(stability.observe(tall, at: .milliseconds(192)) == false)
        let settled = stability.observe(tall, at: .milliseconds(248))
        #expect(settled)
        #expect(stability.observedChange)
    }

    @Test func normalizesChannelOrderAndIgnoresRowPadding() throws {
        let rgba = try settleTestImage([40, 100, 200, 255])
        let bgra = try settleTestImage(
            [200, 100, 40, 255, 77, 88, 99, 111],
            rowPadding: 4,
            bitmapInfo: [
                .byteOrder32Little,
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),
            ],
        )
        var stability = SnapshotPixelStability()

        #expect(stability.observe(rgba, at: .zero) == false)
        #expect(stability.observe(bgra, at: .milliseconds(64)) == false)
        let settled = stability.observe(bgra, at: .milliseconds(120))
        #expect(settled)
        #expect(stability.observedChange == false)
    }
}
