import CoreGraphics
import Observation
import SwiftUI

@Observable
final class FramingViewModel {

    var importedPhoto: ImportedPhoto?
    var configuration: FramingConfiguration = .default
    var framedPreview: CGImage?
    var isExporting = false
    var exportError: Error?
    var showExportSuccess = false

    func importImage(_ cgImage: CGImage) {
        importedPhoto = ImportedPhoto(cgImage: cgImage)
        updatePreview()
    }

    func updatePreview() {
        guard let photo = importedPhoto else {
            framedPreview = nil
            return
        }

        // Render preview at reduced resolution for responsiveness.
        var previewConfig = configuration
        previewConfig.outputResolution = 1200

        framedPreview = FramingService.frame(
            image: photo.cgImage,
            configuration: previewConfig
        )
    }

    func exportToPhotoLibrary() async {
        guard let photo = importedPhoto else { return }

        isExporting = true
        defer { isExporting = false }

        // Render at full resolution for export.
        guard let fullRes = FramingService.frame(
            image: photo.cgImage,
            configuration: configuration
        ) else {
            exportError = PhotoExporter.ExportError.encodingFailed
            return
        }

        do {
            try await PhotoExporter.saveToPhotoLibrary(fullRes)
            showExportSuccess = true
        } catch {
            exportError = error
        }
    }

    func framedImageForFileExport() -> FramedImageDocument? {
        guard let photo = importedPhoto else { return nil }

        guard let fullRes = FramingService.frame(
            image: photo.cgImage,
            configuration: configuration
        ) else { return nil }

        return FramedImageDocument(image: fullRes)
    }

    func reset() {
        importedPhoto = nil
        framedPreview = nil
        configuration = .default
        exportError = nil
        showExportSuccess = false
    }
}
