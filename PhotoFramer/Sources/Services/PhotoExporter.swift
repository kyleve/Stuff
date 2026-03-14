import CoreGraphics
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Export to Photo Library

enum PhotoExporter {

    enum ExportError: LocalizedError {
        case notAuthorized
        case saveFailed(Error)
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                "Photo library access not authorized."
            case .saveFailed(let error):
                "Failed to save photo: \(error.localizedDescription)"
            case .encodingFailed:
                "Failed to encode image."
            }
        }
    }

    static func saveToPhotoLibrary(_ image: CGImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.notAuthorized
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.95) else {
                return
            }
            request.addResource(with: .photo, data: data, options: nil)
        }
    }

    static func saveToFile(_ image: CGImage, url: URL, format: ImageFormat) throws {
        let data: Data
        let uiImage = UIImage(cgImage: image)

        switch format {
        case .jpeg(let quality):
            guard let encoded = uiImage.jpegData(compressionQuality: quality) else {
                throw ExportError.encodingFailed
            }
            data = encoded
        case .png:
            guard let encoded = uiImage.pngData() else {
                throw ExportError.encodingFailed
            }
            data = encoded
        }

        try data.write(to: url, options: .atomic)
    }

    enum ImageFormat {
        case jpeg(quality: CGFloat)
        case png
    }
}

// MARK: - Transferable for fileExporter

struct FramedImageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }

    let imageData: Data

    init(image: CGImage) {
        self.imageData = UIImage(cgImage: image).pngData() ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        self.imageData = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: imageData)
    }
}
