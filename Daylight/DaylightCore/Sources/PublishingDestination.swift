import Foundation

public protocol PublishingDestination: Sendable {
    var id: PublishingDestinationID { get }
    var inputs: Set<PublishingInput.Kind> { get }
    func isEnabled() async -> Bool
    func deliver(
        _ input: PublishingInput,
        deliveryID: PublishingDelivery.ID,
        checkpoint: Data?,
        saveCheckpoint: @escaping @Sendable (Data) async throws -> Void,
    ) async throws
        -> PublishingReceipt
}
