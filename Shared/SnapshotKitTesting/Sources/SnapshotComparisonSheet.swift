import SnapshotKit
import SnapshotTesting
import UIKit

/// Pixel-space panel geometry accompanies the sheet so a layout change cannot
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

/// Composes captures without scaling and compares each subject at the ordinary
/// image tolerance. Adding panels cannot dilute a local regression.
@MainActor
struct SnapshotComparisonSheet {
    struct Panel {
        let identity: SnapshotPanel.ID
        let label: String
        let image: UIImage
    }

    let image: UIImage
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
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        format.preferredRange = .standard
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (panel, placement) in zip(panels, placements) {
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
        image = decoded
    }

    enum Failure: Error {
        case invalidPanels
        case mixedScales
        case oversizedSheet
    }

    /// The whole-sheet check guards labels and spacing. Panel checks preserve
    /// the area budget of each individually captured component.
    static func strategy(layout: SnapshotComparisonLayout) -> Snapshotting<UIImage, UIImage> {
        var strategy: Snapshotting<UIImage, UIImage> = .image(
            precision: defaultSnapshotPrecision,
            perceptualPrecision: defaultSnapshotPerceptualPrecision,
        )
        let original = strategy.diffing
        strategy.diffing = Diffing(
            toData: original.toData,
            fromData: original.fromData,
            diff: { reference, actual in
                guard let old = reference.cgImage, let new = actual.cgImage,
                      old.width == new.width, old.height == new.height,
                      new.width == Int(layout.pixelSize.width),
                      new.height == Int(layout.pixelSize.height)
                else { return (
                    "Comparison sheet dimensions do not match the approved panel layout",
                    [],
                ) }
                for panel in layout.panels {
                    guard let oldPanel = old.cropping(to: panel.bounds),
                          let newPanel = new.cropping(to: panel.bounds)
                    else { return ("Invalid comparison bounds for \(panel.label)", []) }
                    if let failure = original.diff(
                        UIImage(cgImage: oldPanel, scale: reference.scale, orientation: .up),
                        UIImage(cgImage: newPanel, scale: actual.scale, orientation: .up),
                    ) {
                        return (
                            "Panel \(panel.label) (\(panel.identity.rawValue)): \(failure.0)",
                            failure.1,
                        )
                    }
                }
                return original.diff(reference, actual)
            },
        )
        return strategy
    }
}
