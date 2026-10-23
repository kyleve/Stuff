import SnapshotKit
@_spi(Testing) @testable import SnapshotKitTesting
import SwiftUI
import Testing

@MainActor
struct AssertComparisonSnapshotsTests {
    @Test(arguments: [ColorScheme.light, .dark], [
        SnapshotConfiguration.Frame.component,
        .init(name: "Fixed", size: .fixed(CGSize(width: 160, height: 100))),
    ])
    func transparentPanelsMatchTheirSheet(
        colorScheme: ColorScheme,
        frame: SnapshotConfiguration.Frame,
    ) async throws {
        let configuration = SnapshotConfiguration(colorScheme: colorScheme, device: frame)
        let snapshotCase = transparentCase(color: .black)
        let panels = try await captureSnapshotPanels(snapshotCase, configuration: configuration)
        let margin = panels[0].image.probePixel(atUnitPoint: CGPoint(x: 0.01, y: 0.5))
        #expect(margin.alpha == 1)
        #expect(margin.red == 1 && margin.green == 1 && margin.blue == 1)
        let center = panels[0].image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5))
        #expect(center.alpha == 1)
        #expect(abs(center.red - 0.5) < 0.02)
        let ownBackground = panels[1].image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5))
        #expect(ownBackground.alpha == 1)
        #expect(ownBackground.red == 0 && ownBackground.green == 0 && ownBackground.blue == 0)

        let sheet = try await SnapshotImageGrid.capture(panels: panels, named: "Transparent")
        let png = try sheet.pngData()
        #expect(SnapshotImageReference.comparePanels(referencePNG: png, panels: panels) == nil)
        let changed = try await captureSnapshotPanels(
            transparentCase(color: .red),
            configuration: configuration,
        )
        #expect(SnapshotImageReference.comparePanels(referencePNG: png, panels: changed)?
            .message.contains("Panel Transparent") == true)
    }

    private func transparentCase(color: Color) -> SnapshotCase {
        SnapshotCase.cutsheet(name: "Transparent", configurations: [], settle: .immediate) {
            SnapshotPanel(id: .init(rawValue: "transparent"), label: "Transparent") {
                color.opacity(0.5).frame(width: 40, height: 40).padding(20)
            }
            SnapshotPanel(id: .init(rawValue: "opaque"), label: "Opaque") {
                Color.black.frame(width: 80, height: 80)
            }
        }
    }

    @Test func hostsFreshPanelsAndRunsBothReadinessHooks() async throws {
        var builds = 0
        var measurementHooks = 0
        var captureHooks = 0
        let snapshotCase = SnapshotCase.cutsheet(
            name: "Hooks",
            configurations: [SnapshotConfiguration()],
            measurementReadiness: .immediate,
            onReadyToMeasure: { measurementHooks += 1 },
            settle: .immediate,
            onReadyToSnapshot: { captureHooks += 1 },
        ) {
            for identity in ["one", "two"] {
                SnapshotPanel(id: .init(rawValue: identity), label: identity) {
                    builds += 1
                    return Color.blue.frame(height: 40)
                }
            }
        }
        #expect(builds == 0)
        let result = try await captureSnapshotPanels(
            snapshotCase,
            configuration: SnapshotConfiguration(),
        )
        let grid = try await SnapshotImageGrid.capture(panels: result, named: "Hooks")
        #expect(builds == 2)
        #expect(measurementHooks == 2)
        #expect(captureHooks == 2)
        #expect(grid.layout?.panels.count == 2)
    }

    @Test func accessibilityPanelsUseTheAnnotationPipeline() async throws {
        let snapshotCase = SnapshotCase.cutsheet(
            name: "Accessibility",
            configurations: [],
            settle: .immediate,
        ) {
            SnapshotPanel(id: .init(rawValue: "one"), label: "One") {
                Text("Accessible subject").padding()
            }
        }
        let standard = try await captureSnapshotPanels(
            snapshotCase,
            configuration: SnapshotConfiguration(),
        )
        let annotated = try await captureSnapshotPanels(
            snapshotCase,
            configuration: SnapshotConfiguration(snapshotType: .accessibility),
        )
        #expect(annotated[0].image.pngData() != standard[0].image.pngData())
        #expect(annotated[0].image.size.height > standard[0].image.size.height)
    }
}
