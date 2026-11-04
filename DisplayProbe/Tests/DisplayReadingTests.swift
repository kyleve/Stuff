@testable import DisplayProbe
import Testing
import UIKit

struct DisplayReadingTests {
    @Test func preservesNativeAxesAndDistinctScalesForRotatedPartialWindow() throws {
        let reading = DisplayReading(
            screen: .init(
                bounds: CGRect(x: 0, y: 0, width: 900, height: 600),
                nativeBounds: CGRect(x: 0, y: 0, width: 1800, height: 2700),
                scale: 2,
                nativeScale: 3,
                pointsPerInch: .available(142.5),
                modePixels: CGSize(width: 1800, height: 2700),
                maximumFramesPerSecond: 120,
            ),
            window: .init(
                sceneBounds: CGRect(x: 0, y: 0, width: 450, height: 600),
                bounds: CGRect(x: 0, y: 0, width: 450, height: 600),
                safeArea: UIEdgeInsets(top: 20, left: 0, bottom: 10, right: 0),
                orientation: .landscapeLeft,
            ),
        )
        func field(_ label: String) throws -> String {
            try #require(reading.fields.first { $0.label == label }).value
        }
        #expect(try field("Native bounds · pixels") == "1800 × 2700")
        #expect(try field("Screen bounds · points") == "900 × 600")
        #expect(try field("Window bounds · points") == "450 × 600")
        #expect(try field("Rendering scale · scale") == "2×")
        #expect(try field("Native scale · nativeScale") == "3×")
        #expect(try field("Points per inch · _pointsPerInch") == "142.5 pt/in")
        #expect(reading.report.contains("Points per inch · _pointsPerInch: 142.5 pt/in"))
        #expect(reading.report.contains("Interface orientation: Landscape left"))
    }

    @Test @MainActor func unattachedWindowDoesNotFallBackToAnotherScreen() {
        #expect(DisplayReading.capture(window: UIWindow(frame: .zero)) == nil)
    }

    @Test @MainActor func capturesTheWindowsActualScene() throws {
        let scene = try #require(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
        let reading = try #require(DisplayReading.capture(window: window))
        #expect(reading.window.bounds == window.bounds)
        #expect(reading.screen.bounds == scene.screen.bounds)
        #expect(reading.screen.nativeBounds == scene.screen.nativeBounds)
        #expect(reading.screen.scale == scene.screen.scale)
        #expect(reading.screen.nativeScale == scene.screen.nativeScale)
        #expect(reading.screen.pointsPerInch == ScreenPointsPerInch.read(from: scene.screen))
    }
}
