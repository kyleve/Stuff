@_spi(Testing) @testable import DaylightCore
import Foundation
import PeriscopeCore
import Synchronization

final class CaptureTestClock: Sendable {
    private let storage: Mutex<Date>
    init(_ date: Date) {
        storage = Mutex(date)
    }

    var now: Date {
        storage.withLock { $0 }
    }

    func advance(_ seconds: TimeInterval) {
        storage.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

actor ScriptedCamera: CameraCapturing {
    var count = 0
    func requestAccess() -> Bool {
        true
    }

    func availableLenses() -> [CaptureSettings.Camera.Lens] {
        [.main]
    }

    func capture(settings _: CaptureSettings.Camera) -> CameraCapture {
        count +=
            1; return CameraCapture(jpeg: Data("original".utf8), raw: Data("raw".utf8))
    }

    func preview(
        settings _: CaptureSettings.Camera,
    ) -> AsyncThrowingStream<Data, any Error> {
        .init { $0.finish() }
    }

    func stop() {}
}

struct ScriptedSolar: SolarCalculating {
    let event: SolarEvent
    func events(on _: Date, site _: CaptureSettings.Site) -> [SolarEvent] {
        [event]
    }
}

struct ScriptedScorer: ImageScoring {
    func score(_: Data) -> ImageScore {
        .init(overall: 0.7, isUtility: false)
    }
}

actor ScriptedPhotos: PhotosSaving {
    var count = 0
    func requestAccess() -> Bool {
        true
    }

    func contains(assetIdentifier: String) -> Bool {
        assetIdentifier == "saved"
    }

    func save(
        originalURL _: URL,
        rawURL _: URL?,
        capturedAt _: Date,
        recordIdentifier: @escaping @Sendable (String) async throws -> Void,
    ) async throws -> String {
        count += 1; try await recordIdentifier("saved"); return "saved"
    }
}

actor ScriptedPublisher: PublishingDestination {
    nonisolated let id = PublishingDestinationID(rawValue: "probe")
    nonisolated let inputs: Set<PublishingInput.Kind> = [.sequenceHighlight]
    var count = 0
    func isEnabled() -> Bool {
        true
    }

    func recover(checkpoint: Data?, action: PublishingRecoveryAction) -> PublishingRecoveryResult {
        switch action {
            case .retry: .retry(checkpoint: checkpoint)
            case .confirmedAbsent: .retry(checkpoint: nil)
            case let .published(url): .delivered(PublishingReceipt(
                    remoteID: url.lastPathComponent,
                    url: url,
                ))
        }
    }

    func deliver(
        _: PublishingInput,
        deliveryID _: PublishingDelivery.ID,
        checkpoint _: Data?,
        saveCheckpoint: @escaping @Sendable (Data) async throws -> Void,
    ) async throws -> PublishingReceipt {
        count += 1
        try await saveCheckpoint(Data("checkpoint".utf8))
        return PublishingReceipt(remoteID: "post", url: URL(string: "https://example.com/post")!)
    }
}

struct CaptureHarness {
    let root: URL
    let store: CaptureStore
    let clock: CaptureTestClock
    let camera = ScriptedCamera()
    let publisher = ScriptedPublisher()
    let event: SolarEvent
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try CaptureStore(root: root)
        event = SolarEvent(
            id: .init(year: 2026, month: 6, day: 21, kind: .sunrise),
            date: Date(timeIntervalSince1970: 1_782_046_800),
        )
        clock = CaptureTestClock(event.date.addingTimeInterval(-1800))
    }

    func engine(photos: any PhotosSaving, scorer: any ImageScoring) -> CaptureEngine {
        CaptureEngine(
            store: store,
            camera: camera,
            solar: ScriptedSolar(event: event),
            photos: photos,
            scorer: scorer,
            destinations: [publisher],
            log: Log<DaylightLogEvent>(system: Periscope(
                configuration: .init(),
                sinks: [],
            )),
            now: { clock.now },
        )
    }

    func clean() throws {
        try FileManager.default.removeItem(at: root)
    }
}

struct FailingPhotos: PhotosSaving {
    func requestAccess() -> Bool {
        false
    }

    func contains(assetIdentifier _: String) -> Bool {
        false
    }

    func save(
        originalURL _: URL,
        rawURL _: URL?,
        capturedAt _: Date,
        recordIdentifier _: @escaping @Sendable (String) async throws -> Void,
    ) throws
        -> String
    {
        throw PhotosSaveFailure(message: DaylightError.photosPermission.localizedDescription)
    }
}

struct FailingScorer: ImageScoring {
    func score(_: Data) throws -> ImageScore {
        throw DaylightError.invalidImage
    }
}

actor GatedPublisher: PublishingDestination {
    nonisolated let id = PublishingDestinationID(rawValue: "gated")
    nonisolated let inputs: Set<PublishingInput.Kind> = [.sequenceHighlight]
    private var entered = false
    private var enterWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func isEnabled() async -> Bool {
        entered = true
        enterWaiter?.resume(); enterWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
        return true
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enterWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume(); releaseWaiter = nil
    }

    func recover(checkpoint: Data?, action: PublishingRecoveryAction) -> PublishingRecoveryResult {
        switch action {
            case .retry: .retry(checkpoint: checkpoint)
            case .confirmedAbsent: .retry(checkpoint: nil)
            case let .published(url): .delivered(PublishingReceipt(
                    remoteID: url.lastPathComponent,
                    url: url,
                ))
        }
    }

    func deliver(
        _ input: PublishingInput,
        deliveryID _: PublishingDelivery.ID,
        checkpoint _: Data?,
        saveCheckpoint _: @escaping @Sendable (Data) async throws -> Void,
    ) throws -> PublishingReceipt {
        _ = try Data(contentsOf: input.imageURL)
        return PublishingReceipt(remoteID: "gated", url: URL(string: "https://example.com/gated")!)
    }
}
