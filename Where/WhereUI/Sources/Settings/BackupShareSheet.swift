import SwiftUI
import UIKit

/// Presents the system activity sheet for a completed backup archive.
///
/// `ShareLink` does not present reliably for this file on a physical device,
/// so the SwiftUI sheet owns UIKit's direct activity-controller bridge.
struct BackupShareSheet: UIViewControllerRepresentable {
    struct Item: Identifiable {
        let url: URL

        var id: URL {
            url
        }
    }

    let item: Item

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [item.url], applicationActivities: nil)
    }

    func updateUIViewController(
        _: UIActivityViewController,
        context _: Context,
    ) {}
}

#if DEBUG
    #Preview {
        BackupShareSheet(
            item: .init(url: URL(fileURLWithPath: "/tmp/Where Backup.zip")),
        )
    }
#endif
