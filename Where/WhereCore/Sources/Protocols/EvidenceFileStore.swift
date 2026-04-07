import Foundation

public protocol EvidenceFileStore: Sendable {
    func save(_ data: Data, for attachment: EvidenceAttachment) async
    func load(for attachment: EvidenceAttachment) async -> Data?
    func delete(for attachment: EvidenceAttachment) async
}
