import SnapshotKit
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
