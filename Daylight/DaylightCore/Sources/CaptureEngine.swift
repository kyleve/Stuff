import Foundation
import PeriscopeCore

/// One orchestration owner. Capture and delivery loops may interleave, but mutate current records
/// by identity.
public actor CaptureEngine: CaptureControlling {
    private let manual: ManualCaptureService
    private let store: CaptureStore
    private let camera: any CameraCapturing
    private let solar: any SolarCalculating

    private let photos: any PhotosSaving
    private let scorer: any ImageScoring
    private let destinations: [any PublishingDestination]
    private let log: Log<DaylightLogEvent>
    private let now: @Sendable () -> Date
    private var sequences: [SolarEvent.ID: CaptureSequence] = [:]
    private var settings = CaptureSettings.standard
    private var captureBusy = false
    private var publishingBusy = false
    private var loaded = false

    public init(
        store: CaptureStore,
        camera: any CameraCapturing,
        solar: any SolarCalculating,
        photos: any PhotosSaving,
        scorer: any ImageScoring,
        destinations: [any PublishingDestination],
        log: Log<DaylightLogEvent>,
        now: @escaping @Sendable () -> Date,
    ) {
        precondition(Set(destinations.map(\.id)).count == destinations.count)
        manual = ManualCaptureService(
            store: store,
            camera: camera,
            photos: photos,
        )
        self.store = store; self.camera = camera; self.solar = solar
        self.photos = photos; self.scorer = scorer; self.destinations = destinations; self
            .log = log; self.now = now
    }

    public func armedIntent() async throws -> Bool {
        try await store.armedIntent()
    }

    public func setArmedIntent(_ armed: Bool) async throws {
        try await store.setArmedIntent(armed)
    }

    public func load() async throws -> CaptureSettings {
        guard !loaded else { return settings }
        settings = try await store.settings()
        let saved = try await store.sequences()
        guard Set(saved.map(\.id)).count == saved.count else { throw DaylightError.invalidStore }
        sequences = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
        loaded = true
        return settings
    }

    public func configure(_ value: CaptureSettings) async throws {
        try value.validate()
        try await store.saveSettings(value)
        settings = value
    }

    public func history() -> [CaptureSequence] {
        sequences.values
            .sorted { $0.event.date > $1.event.date }
    }

    public func nextCapture() -> Date? {
        sequences.values.flatMap(\.slots).filter {
            if case .pending = $0.state { return $0.scheduledAt >= now().addingTimeInterval(-30) }
            return false
        }.map(\.scheduledAt).min()
    }

    private func persist(_ sequenceID: SolarEvent.ID) async throws {
        guard let sequence = sequences[sequenceID] else { throw DaylightError.invalidStore }
        try await store.save(sequence)
    }

    public func plan() async throws {
        guard loaded else { throw DaylightError.invalidStore }
        guard let zone = TimeZone(identifier: settings.site.timeZoneIdentifier)
        else { throw DaylightError.invalidSettings }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        for offset in 0 ... 1 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: now())
            else { throw DaylightError.invalidSettings }
            for event in try solar.events(on: date, site: settings.site) {
                if let existing = sequences[event.id] {
                    let untouched = existing.slots
                        .allSatisfy { if case .pending = $0.state { true } else { false } }
                    if untouched, existing.settings != settings {
                        sequences[event.id] = CaptureSequence(event: event, settings: settings)
                        try await persist(event.id)
                    }
                } else {
                    sequences[event.id] = CaptureSequence(event: event, settings: settings)
                    try await persist(event.id)
                }
            }
        }
    }

    public func tick(canCapture: Bool) async throws {
        guard !captureBusy else { return }
        captureBusy = true
        defer { captureBusy = false }
        if canCapture { try await store.requireAvailableSpace() }
        try await plan()
        for sequenceID in history().reversed().map(\.id) {
            guard let initial = sequences[sequenceID] else { continue }
            for index in initial.slots.indices {
                guard let slot = sequences[sequenceID]?.slots[index] else { continue }
                switch slot.state {
                    case .pending:
                        let lateness = now().timeIntervalSince(slot.scheduledAt)
                        if lateness > 30 {
                            sequences[sequenceID]?.slots[index].state = .missed
                            try await persist(sequenceID)
                        } else if lateness >= 0, canCapture {
                            try await capture(sequenceID: sequenceID, index: index)
                        }
                    case .capturing:
                        // A prior process stopped before recording completion. Never recapture the
                        // same slot.
                        let url = await store.imageURL(slot.id, resource: .original)
                        if FileManager.default.fileExists(atPath: url.path) {
                            sequences[sequenceID]?.slots[index]
                                .state = await .captured(CapturedImage(
                                    id: slot.id,
                                    capturedAt: slot.scheduledAt,
                                    format: store.rawURL(slot.id) == nil ? .jpeg : .rawAndJPEG,
                                ))
                        } else {
                            sequences[sequenceID]?.slots[index]
                                .state = .failed(DaylightError.interrupted.localizedDescription)
                        }
                        try await persist(sequenceID)
                    case .captured, .failed, .missed: break
                }
                if case .captured = sequences[sequenceID]?.slots[index].state {
                    try await finishImage(sequenceID: sequenceID, index: index)
                }
            }
            if let sequence = sequences[sequenceID], now() > sequence.end,
               case .pending = sequence.selection
            {
                do {
                    let selected = try ImageSelector().select(from: sequence)
                    sequences[sequenceID]?.selection = .selected(selected.id)
                    try await enqueue(
                        image: selected,
                        sequenceID: sequenceID,
                        kind: .sequenceHighlight,
                    )
                } catch {
                    sequences[sequenceID]?.selection = .failed(error.localizedDescription)
                    log.warning("Image selection failed; sequence preserved.")
                }
                try await persist(sequenceID)
            }
        }
        try await manual.recover()
    }

    private func capture(sequenceID: SolarEvent.ID, index: Int) async throws {
        guard let sequence = sequences[sequenceID] else { throw DaylightError.invalidStore }
        let slot = sequence.slots[index]
        sequences[sequenceID]?.slots[index].state = .capturing
        try await persist(sequenceID)
        do {
            let bytes = try await camera.capture(settings: sequence.settings.camera)
            try await store.stageCapture(bytes, imageID: slot.id)
            sequences[sequenceID]?.slots[index].state = .captured(CapturedImage(
                id: slot.id,
                capturedAt: now(),
                format: bytes.raw == nil ? .jpeg : .rawAndJPEG,
            ))
            try await persist(sequenceID)
        } catch {
            sequences[sequenceID]?.slots[index].state = .failed(error.localizedDescription)
            try await persist(sequenceID)
            log.warning("Camera capture failed; slot recorded.")
            throw error
        }
    }

    private func setImage(
        _ image: CapturedImage,
        sequenceID: SolarEvent.ID,
        index: Int,
    ) async throws {
        sequences[sequenceID]?.slots[index].state = .captured(image)
        try await persist(sequenceID)
    }

    private func finishImage(sequenceID: SolarEvent.ID, index: Int) async throws {
        guard case var .captured(image) = sequences[sequenceID]?.slots[index].state else { return }
        let original = await store.imageURL(image.id, resource: .original)
        if case .saved = image.photos, case .scored = image.score {
            try await queueCapturedImage(&image, sequenceID: sequenceID, index: index)
            return
        }
        switch image.photos {
            case .pending:
                image.photos = .saving(nil)
                try await setImage(image, sequenceID: sequenceID, index: index)
                do {
                    let asset = try await photos.save(
                        originalURL: original,
                        rawURL: store.rawURL(image.id),
                        capturedAt: image.capturedAt,
                    ) { [weak self] identifier in
                        try await self?.recordPhotosIdentifier(
                            identifier,
                            sequenceID: sequenceID,
                            index: index,
                        )
                    }
                    image.photos = .saved(asset)
                } catch {
                    image.photos = .ambiguous
                    log
                        .warning(
                            "Photos save interrupted; staged files preserved for reconciliation.",
                        )
                }
            case let .saving(identifier):
                let receipt = original.deletingPathExtension()
                    .appendingPathExtension("photos-receipt")
                let recorded: String
                if let identifier { recorded = identifier }
                else if FileManager.default
                    .fileExists(atPath: receipt.path)
                { recorded = try String(
                    contentsOf: receipt,
                    encoding: .utf8,
                ) } else { image.photos = .ambiguous; try await setImage(
                    image,
                    sequenceID: sequenceID,
                    index: index,
                ); return }
                image.photos = try await photos
                    .contains(assetIdentifier: recorded) ? .saved(recorded) : .ambiguous
            case .saved, .failed, .ambiguous: break
        }
        if case .pending = image.score {
            do { image.score = try await .scored(scorer.score(Data(contentsOf: original))) }
            catch {
                image.score = .failed(error.localizedDescription); log
                    .warning("Local scoring failed; image preserved.")
            }
        }
        try await setImage(image, sequenceID: sequenceID, index: index)
        try await queueCapturedImage(&image, sequenceID: sequenceID, index: index)
    }

    private func queueCapturedImage(
        _ image: inout CapturedImage,
        sequenceID: SolarEvent.ID,
        index: Int,
    ) async throws {
        guard !image.capturedEventHandled else { return }
        try await enqueue(image: image, sequenceID: sequenceID, kind: .capturedImage)
        image.capturedEventHandled = true
        try await setImage(image, sequenceID: sequenceID, index: index)
    }

    private func recordPhotosIdentifier(
        _ identifier: String,
        sequenceID: SolarEvent.ID,
        index: Int,
    ) async throws {
        guard case var .captured(image) = sequences[sequenceID]?.slots[index].state
        else { throw DaylightError.invalidStore }
        image.photos = .saving(identifier)
        try await setImage(image, sequenceID: sequenceID, index: index)
    }

    private func enqueue(
        image: CapturedImage,
        sequenceID: SolarEvent.ID,
        kind: PublishingInput.Kind,
    ) async throws {
        for destination in destinations where destination.inputs.contains(kind) {
            guard await destination.isEnabled() else { continue }
            let exists = sequences[sequenceID]?.deliveries
                .contains {
                    $0.destination == destination.id && $0.imageID == image.id && $0.kind == kind
                } ==
                true
            if !exists {
                sequences[sequenceID]?.deliveries.append(PublishingDelivery(
                    destination: destination.id,
                    imageID: image.id,
                    kind: kind,
                ))
                try await persist(sequenceID)
            }
        }
    }

    public func publishPending() async throws {
        guard !publishingBusy else { return }
        publishingBusy = true
        defer { publishingBusy = false }
        for sequenceID in history().reversed().map(\.id) {
            guard let sequence = sequences[sequenceID] else { continue }
            for delivery in sequence.deliveries {
                switch delivery.state {
                    case .pending: break
                    case let .retry(date, _): if date > now() { continue }
                    case .delivered, .needsAttention: continue
                }
                guard let destination = destinations.first(
                    where: { $0.id == delivery.destination },
                ),
                    await destination.isEnabled(),
                    let image = sequence.images.first(where: { $0.id == delivery.imageID })
                else { continue }
                let input = await PublishingInput(
                    kind: delivery.kind,
                    image: image,
                    event: sequence.event,
                    timeZoneIdentifier: sequence.settings.site.timeZoneIdentifier,
                    imageURL: store.imageURL(image.id, resource: .original),
                    rawURL: store.rawURL(image.id),
                )
                guard let attemptIndex = sequences[sequenceID]?.deliveries
                    .firstIndex(where: { $0.id == delivery.id })
                else { throw DaylightError.invalidStore }
                sequences[sequenceID]?.deliveries[attemptIndex].attempts += 1
                try await persist(sequenceID)
                let backoff = min(3600.0, 30 * pow(2, Double(min(delivery.attempts, 7))))
                let state: PublishingDelivery.State
                do {
                    let receipt = try await destination.deliver(
                        input,
                        deliveryID: delivery.id,
                        checkpoint: delivery.checkpoint,
                    ) { [weak self] data in
                        try await self?.checkpoint(
                            data,
                            deliveryID: delivery.id,
                            sequenceID: sequenceID,
                        )
                    }
                    state = .delivered(receipt)
                } catch let PublishingFailure
                    .retry(after, message)
                { state = .retry(
                    max(after, now().addingTimeInterval(backoff)),
                    message,
                ) } catch let PublishingFailure
                    .needsAttention(message) { state = .needsAttention(message) }
                catch is CancellationError { return }
                catch {
                    state = .retry(
                        now().addingTimeInterval(backoff),
                        error.localizedDescription,
                    ); log
                        .warning("Publishing failed; delivery remains queued.")
                }
                guard let index = sequences[sequenceID]?.deliveries
                    .firstIndex(where: { $0.id == delivery.id })
                else { throw DaylightError.invalidStore }
                sequences[sequenceID]?.deliveries[index].state = state
                try await persist(sequenceID)
            }
            try await cleanCompleted(sequenceID)
        }
    }

    private func checkpoint(
        _ data: Data,
        deliveryID: PublishingDelivery.ID,
        sequenceID: SolarEvent.ID,
    ) async throws {
        guard let index = sequences[sequenceID]?.deliveries
            .firstIndex(where: { $0.id == deliveryID }) else { throw DaylightError.invalidStore }
        sequences[sequenceID]?.deliveries[index].checkpoint = data
        try await persist(sequenceID)
    }

    private func cleanCompleted(_ sequenceID: SolarEvent.ID) async throws {
        guard let sequence = sequences[sequenceID],
              case .selected = sequence.selection else { return }
        for image in sequence.images {
            guard case .saved = image.photos, case .scored = image.score else { continue }
            let delivered = sequence.deliveries.filter { $0.imageID == image.id }
                .allSatisfy { if case .delivered = $0.state { true } else { false } }
            if delivered { try await store.removeStagedFiles(imageID: image.id) }
        }
    }

    public func manualHistory() async throws -> [ManualCapture] {
        try await store.manualCaptures()
    }

    public func manualCapture() async throws {
        guard !captureBusy else { throw DaylightError.interrupted }
        captureBusy = true
        defer { captureBusy = false }
        try await store.requireAvailableSpace()
        try await manual.capture(settings: settings, date: now())
    }
}
