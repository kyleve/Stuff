import SnapshotKit
@testable import SnapshotKitTesting
import UIKit

@MainActor
func comparisonPanel(
    _ name: String,
    height: CGFloat = 80,
    scale: CGFloat = 1,
    changed: Bool = false,
) -> SnapshotComparisonSheet.Panel {
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    let image = UIGraphicsImageRenderer(
        size: CGSize(width: 100, height: height),
        format: format,
    ).image { context in
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 100, height: height))
        if changed {
            UIColor.black.setFill()
            context.fill(CGRect(x: 20, y: 20, width: 4, height: 4))
        }
    }
    return .init(identity: .init(rawValue: name), label: name, image: image)
}
