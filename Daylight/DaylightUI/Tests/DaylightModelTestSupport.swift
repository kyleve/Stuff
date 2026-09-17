import DaylightCore
import Foundation

actor PreviewTestCamera: CameraCapturing {
    let allowed: Bool
    let frame: Data
    private(set) var accessRequests = 0
    private(set) var previewStarts = 0
    private(set) var stops = 0

    init(allowed: Bool, frame: Data) {
        self.allowed = allowed; self.frame = frame
    }

    func requestAccess() -> Bool {
        accessRequests += 1
        return allowed
    }

    func availableLenses() -> [CaptureSettings.Camera.Lens] {
        [.main]
    }

    func capture(settings _: CaptureSettings.Camera) throws -> CameraCapture {
        throw DaylightError.unavailableCamera
    }

    func preview(settings _: CaptureSettings.Camera) -> AsyncThrowingStream<Data, any Error> {
        previewStarts += 1
        return AsyncThrowingStream { continuation in
            continuation.yield(frame)
            continuation.finish()
        }
    }

    func stop() {
        stops += 1
    }
}

actor ModelTestGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }
}

actor LifecycleTestController: CaptureControlling {
    let tickEntered = ModelTestGate()
    let releaseTick = ModelTestGate()
    let nextTick = ModelTestGate()
    let publishingEntered = ModelTestGate()
    let releasePublishing = ModelTestGate()
    private var ticks = 0
    private var publishingCalls = 0
    private var armed = true
    let blockTick: Bool
    let blockPublishing: Bool
    init(blockTick: Bool, blockPublishing: Bool) {
        self.blockTick = blockTick; self.blockPublishing = blockPublishing
    }

    func armedIntent() -> Bool {
        armed
    }

    func setArmedIntent(_ value: Bool) {
        armed = value
    }

    func load() -> CaptureSettings {
        .standard
    }

    func configure(_: CaptureSettings) {}
    func plan() {}
    func tick(canCapture _: Bool) async {
        ticks += 1
        if ticks == 1 {
            await tickEntered.open()
            if blockTick { await releaseTick.wait() }
        } else { await nextTick.open() }
    }

    func publishPending() async {
        publishingCalls += 1
        if publishingCalls == 1 {
            await publishingEntered.open()
            if blockPublishing { await releasePublishing.wait() }
        }
    }

    func history() -> [CaptureSequence] {
        []
    }

    func nextCapture() -> Date? {
        nil
    }

    func manualHistory() -> [ManualCapture] {
        []
    }

    func recoverDelivery(
        sequenceID _: SolarEvent.ID,
        deliveryID _: PublishingDelivery.ID,
        action _: PublishingRecoveryAction,
    ) {}
    func resolvePhotos(imageID _: CaptureSequence.Slot.ID, resolution _: PhotosResolution) {}
    func manualCapture() {}
}
