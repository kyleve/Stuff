import SnapshotKit
import SwiftUI
import TestHostSupport
import UIKit

/// SwiftUI lays out captured pixels and labels; the shared renderer captures the grid.
/// Geometry observations supply the panel map without a second layout algorithm.
@MainActor
struct SnapshotImageGrid: View {
    static let backgroundColor = UIColor.white

    let panels: [SnapshotPanelCapture]
    let measurement: Measurement
    @Namespace private var coordinateSpace

    var body: some View {
        let space = coordinateSpace
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
            ForEach(Array(stride(from: 0, to: panels.count, by: 2)), id: \.self) { start in
                GridRow(alignment: .top) {
                    ForEach(
                        panels[start ..< min(start + 2, panels.count)],
                        id: \.identity,
                    ) { panel in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: panel.label)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(width: panel.image.size.width, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Image(uiImage: panel.image)
                                .onGeometryChange(for: CGRect.self) { geometry in
                                    geometry.frame(in: .named(space))
                                } action: { bounds in
                                    measurement.bounds[panel.identity] = bounds
                                }
                        }
                    }
                }
            }
        }
        .padding(16)
        .fixedSize()
        .coordinateSpace(name: space)
        .background(Color(uiColor: Self.backgroundColor))
    }

    /// This is capture output, not view state: measuring never invalidates the grid.
    final class Measurement {
        var bounds: [SnapshotPanel.ID: CGRect] = [:]
    }

    static func capture(
        panels: [SnapshotPanelCapture],
        named name: String,
    ) async throws -> SnapshotImageReference {
        guard !panels.isEmpty, Set(panels.map(\.identity)).count == panels.count,
              panels.allSatisfy({ $0.image.cgImage != nil })
        else { throw Failure.invalidPanels }
        guard let window = hostKeyWindow() else {
            preconditionFailure("Snapshot image grids require the StuffTestHost key window.")
        }
        let scale = window.traitCollection.displayScale
        guard panels.allSatisfy({ $0.image.scale == scale }) else { throw Failure.mixedScales }
        let measurement = Measurement()
        let controller = makeHostingController(
            for: SnapshotImageGrid(panels: panels, measurement: measurement),
            configuration: SnapshotConfiguration(),
        )
        // Images and fixed-font labels have synchronous ideal sizes. SwiftUI owns
        // both axes; this measurement sets only the capture viewport.
        let size = controller.view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        guard size.width > 0, size.height > 0,
              size.width * scale <= 32000, size.height * scale <= 32000,
              size.width * size.height * scale * scale <= 100_000_000
        else { throw Failure.oversizedGrid }
        controller.view.frame = CGRect(origin: .zero, size: size)
        let image = try await renderSnapshotImage(
            of: controller,
            named: name,
            settle: .settled,
        )
        guard let pixels = image.cgImage else { throw Failure.invalidPanels }
        let canvas = CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
        let placements = try panels.map { panel in
            guard let bounds = measurement.bounds[panel.identity],
                  let original = panel.image.cgImage
            else {
                throw Failure.invalidGeometry
            }
            let pixelBounds = CGRect(
                x: (bounds.minX * scale).rounded(),
                y: (bounds.minY * scale).rounded(),
                width: (bounds.width * scale).rounded(),
                height: (bounds.height * scale).rounded(),
            )
            guard canvas.contains(pixelBounds),
                  pixelBounds.size == CGSize(width: original.width, height: original.height)
            else {
                throw Failure.invalidGeometry
            }
            return SnapshotComparisonLayout.Panel(
                identity: panel.identity,
                label: panel.label,
                bounds: pixelBounds,
            )
        }
        return SnapshotImageReference(image: image, layout: .init(
            panels: placements,
            pixelSize: CGSize(width: pixels.width, height: pixels.height),
        ))
    }

    enum Failure: Error {
        case invalidPanels
        case mixedScales
        case oversizedGrid
        case invalidGeometry
    }
}
