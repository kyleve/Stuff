import Foundation

public protocol CaptureControlling: Sendable {
    func armedIntent() async throws -> Bool
    func setArmedIntent(_ armed: Bool) async throws
    func load() async throws -> CaptureSettings
    func configure(_ settings: CaptureSettings) async throws
    func plan() async throws
    func tick(canCapture: Bool) async throws
    func publishPending() async throws
    func history() async -> [CaptureSequence]
    func nextCapture() async -> Date?
    func manualHistory() async throws -> [ManualCapture]
    func recoverDelivery(
        sequenceID: SolarEvent.ID,
        deliveryID: PublishingDelivery.ID,
        action: PublishingRecoveryAction,
    ) async throws
    func resolvePhotos(imageID: CaptureSequence.Slot.ID, resolution: PhotosResolution) async throws
    func manualCapture() async throws
}
