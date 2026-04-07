import Foundation

public struct EvidenceAttachment: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let manualEntryID: UUID
    public let storageKey: String
    public let originalFilename: String
    public let contentType: String
    public let byteCount: Int
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        manualEntryID: UUID,
        storageKey: String? = nil,
        originalFilename: String,
        contentType: String,
        byteCount: Int,
        createdAt: Date = Date(),
    ) {
        self.id = id
        self.manualEntryID = manualEntryID
        self.storageKey = storageKey ?? id.uuidString
        self.originalFilename = originalFilename
        self.contentType = contentType
        self.byteCount = byteCount
        self.createdAt = createdAt
    }
}
