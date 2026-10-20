import SnapshotKit
import SnapshotTesting
import UIKit

/// Pixel-space panel geometry is embedded in the PNG so a layout change cannot
/// reinterpret approved pixels as a different theme or subject.
struct SnapshotComparisonLayout: Codable, Equatable {
    struct Panel: Codable, Equatable {
        let identity: SnapshotPanel.ID
        let label: String
        let bounds: CGRect
    }

    let panels: [Panel]
    let pixelSize: CGSize
}

/// Plans a grid of independent captures, then composes it without scaling.
/// Rendering is deferred so panel verification can run first.
@MainActor
struct SnapshotComparisonSheet {
    struct Panel {
        let identity: SnapshotPanel.ID
        let label: String
        let image: UIImage
    }

    let panels: [Panel]
    private let size: CGSize
    private let scale: CGFloat
    let layout: SnapshotComparisonLayout

    init(panels: [Panel]) throws {
        guard !panels.isEmpty, Set(panels.map(\.identity)).count == panels.count,
              panels.allSatisfy({ $0.image.cgImage != nil })
        else { throw Failure.invalidPanels }
        let scale = panels[0].image.scale
        guard panels.allSatisfy({ $0.image.scale == scale }) else { throw Failure.mixedScales }
        let gap: CGFloat = 16
        let heading: CGFloat = 32
        let width = panels.map(\.image.size.width).max()!
        var placements: [SnapshotComparisonLayout.Panel] = []
        var y = gap
        for rowStart in stride(from: 0, to: panels.count, by: 2) {
            let row = panels[rowStart ..< min(rowStart + 2, panels.count)]
            for (column, panel) in row.enumerated() {
                placements.append(.init(
                    identity: panel.identity,
                    label: panel.label,
                    bounds: CGRect(
                        x: ((gap + CGFloat(column) * (width + gap)) * scale).rounded(),
                        y: ((y + heading) * scale).rounded(),
                        width: (panel.image.size.width * scale).rounded(),
                        height: (panel.image.size.height * scale).rounded(),
                    ),
                ))
            }
            y += heading + row.map(\.image.size.height).max()! + gap
        }
        let size = CGSize(width: CGFloat(min(2, panels.count)) * (width + gap) + gap, height: y)
        guard size.width * scale <= 32000, size.height * scale <= 32000,
              size.width * size.height * scale * scale <= 100_000_000
        else { throw Failure.oversizedSheet }
        layout = .init(
            panels: placements,
            pixelSize: CGSize(
                width: (size.width * scale).rounded(),
                height: (size.height * scale).rounded(),
            ),
        )
        self.panels = panels
        self.size = size
        self.scale = scale
    }

    /// Composition happens only after independent panel comparison.
    func render() throws -> UIImage {
        let heading: CGFloat = 32
        let width = panels.map(\.image.size.width).max()!
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        format.preferredRange = .standard
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (panel, placement) in zip(panels, layout.panels) {
                let bounds = CGRect(
                    x: placement.bounds.minX / scale,
                    y: placement.bounds.minY / scale,
                    width: placement.bounds.width / scale,
                    height: placement.bounds.height / scale,
                )
                (panel.label as NSString).draw(
                    in: CGRect(
                        x: bounds.minX,
                        y: bounds.minY - heading + 6,
                        width: width,
                        height: heading,
                    ),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                        .foregroundColor: UIColor.black,
                    ],
                )
                panel.image.draw(in: bounds)
            }
        }
        guard let png = rendered.pngData(), let decoded = UIImage(data: png, scale: scale) else {
            throw Failure.invalidPanels
        }
        return decoded
    }

    enum Failure: Error {
        case invalidPanels
        case mixedScales
        case oversizedSheet
    }
}
