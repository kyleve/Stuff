import Foundation

/// User decisions about a retained delivery. Only confirmed absence permits clearing submission
/// uncertainty.
public enum PublishingRecoveryAction: Sendable {
    case retry
    case confirmedAbsent
    case published(URL)
}

public enum PublishingRecoveryResult: Sendable {
    case retry(checkpoint: Data?)
    case delivered(PublishingReceipt)
}
