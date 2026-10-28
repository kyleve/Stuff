import SnapshotKit
import UIKit

/// A settled panel, kept independent until comparison and final composition.
struct SnapshotPanelCapture {
    let identity: SnapshotPanel.ID
    let label: String
    let image: UIImage
}
