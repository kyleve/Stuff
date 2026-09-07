import Foundation

/// Reuses the capture root's camera and archive; manual shots never create delivery events.
actor ManualCaptureService {
    private let store: CaptureStore
    private let camera: any CameraCapturing

    private let photos: any PhotosSaving
    init(
        store: CaptureStore,
        camera: any CameraCapturing,
        photos: any PhotosSaving,
    ) {
        self.store = store; self.camera = camera; self.photos = photos
    }

    func capture(settings: CaptureSettings, date: Date) async throws {
        let record = ManualCapture(date: date)
        try await store.saveManual(record)
        do {
            let original = try await camera.capture(settings: settings.camera)
            try await store.stageCapture(original, imageID: record.id)
            try await finish(record)
        } catch {
            var failure = record
            let existing = try await store.manualCaptures().first { $0.id == record.id }
            if let existing, case .captured = existing.state { throw error }
            failure.state = .failed(error.localizedDescription)
            try await store.saveManual(failure)
            throw error
        }
    }

    func recover() async throws {
        for record in try await store.manualCaptures() {
            switch record.state {
                case .capturing: try await finish(record)
                case let .captured(image):
                    switch image.photos {
                        case .pending, .saving: try await finish(record)
                        case .saved: try await store.removeStagedFiles(imageID: record.id)
                        case .ambiguous, .failed: break
                    }
                case .failed: break
            }
        }
    }

    private func finish(_ record: ManualCapture) async throws {
        var record = record
        let originalURL = await store.imageURL(record.id, resource: .original)
        guard FileManager.default.fileExists(atPath: originalURL.path) else {
            record.state = .failed(DaylightError.interrupted.localizedDescription)
            try await store.saveManual(record)
            return
        }
        var image: CapturedImage = if case let .captured(saved) = record.state { saved }
        else { await CapturedImage(
            id: record.id,
            capturedAt: record.date,
            format: store.rawURL(record.id) == nil ? .jpeg : .rawAndJPEG,
        ) }
        record.state = .captured(image)
        try await store.saveManual(record)
        switch image.photos {
            case .pending:
                image.photos = .saving(nil); record.state = .captured(image)
                try await store.saveManual(record)
                do {
                    let snapshot = record
                    let asset = try await photos.save(
                        originalURL: originalURL,
                        rawURL: store.rawURL(record.id),
                        capturedAt: record.date,
                    ) { [store] identifier in
                        var progress = snapshot
                        guard case var .captured(image) = progress.state
                        else { throw DaylightError.invalidStore }
                        image.photos = .saving(identifier); progress.state = .captured(image)
                        try await store.saveManual(progress)
                    }
                    image.photos = .saved(asset)
                } catch {
                    image.photos = .ambiguous; record.state = .captured(image)
                    try await store.saveManual(record)
                    throw error
                }
            case let .saving(identifier):
                let receipt = originalURL.deletingPathExtension()
                    .appendingPathExtension("photos-receipt")
                let asset: String? = if let identifier { identifier }
                else if FileManager.default.fileExists(atPath: receipt.path) { try String(
                    contentsOf: receipt,
                    encoding: .utf8,
                ) } else { nil }
                if let asset,
                   try await photos
                   .contains(assetIdentifier: asset) { image.photos = .saved(asset) }
                else { image.photos = .ambiguous }
            case .saved, .failed, .ambiguous: break
        }
        record.state = .captured(image)
        try await store.saveManual(record)
        if case .saved = image.photos { try await store.removeStagedFiles(imageID: image.id) }
    }
}
