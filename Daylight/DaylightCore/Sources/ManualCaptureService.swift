import Foundation

/// Reuses the capture root's camera and archive; manual shots never create delivery events.
actor ManualCaptureService {
    private let store: CaptureStore
    private let camera: any CameraCapturing

    private let now: @Sendable () -> Date
    private let photos: any PhotosSaving
    init(
        store: CaptureStore,
        camera: any CameraCapturing,
        photos: any PhotosSaving,
        now: @escaping @Sendable () -> Date,
    ) {
        self.now = now
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
                        case .pending, .saving, .ambiguous, .retry: try await finish(record)
                        case .saved: try await store.removeStagedFiles(imageID: record.id)
                        case .failed: break
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
        if case let .retry(date, _) = image.photos {
            guard date <= now() else { return }
            image.photos = .pending
        }
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
                    let saved = try await store.manualCaptures().first { $0.id == record.id }
                    let identifier: String? = if let saved,
                                                 case let .captured(current) = saved.state,
                                                 case let .saving(identifier) = current
                                                 .photos { identifier } else { nil }
                    image.photos = try PhotosRecovery.failure(
                        error,
                        originalURL: originalURL,
                        recorded: identifier,
                        now: now(),
                    )
                    record.state = .captured(image)
                    try await store.saveManual(record)
                    throw error
                }
            case .saving, .ambiguous:
                let recorded: String? = if case let .saving(identifier) = image
                    .photos { identifier } else { nil }
                if let identifier = try PhotosRecovery.identifier(
                    originalURL: originalURL,
                    recorded: recorded,
                ) {
                    image.photos = try await photos
                        .contains(assetIdentifier: identifier) ? .saved(identifier) : .ambiguous
                } else { image.photos = .ambiguous }
            case .saved, .failed, .retry: break
        }
        record.state = .captured(image)
        try await store.saveManual(record)
        if case .saved = image.photos { try await store.removeStagedFiles(imageID: image.id) }
    }
}
