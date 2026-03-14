import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PhotoDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: (CGImage) -> Void

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.image])
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false

        guard let provider = info.itemProviders(for: [.image]).first else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data,
                  let uiImage = UIImage(data: data),
                  let cgImage = uiImage.cgImage
            else { return }

            DispatchQueue.main.async {
                onDrop(cgImage)
            }
        }

        return true
    }
}
