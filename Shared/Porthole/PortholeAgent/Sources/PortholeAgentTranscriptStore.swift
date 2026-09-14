import Foundation

public protocol PortholeAgentTranscriptStoring: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

/// Stores one transcript atomically within the host's application data directory.
public struct PortholeAgentFileTranscriptStore: PortholeAgentTranscriptStoring, Sendable {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func save(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
            try data.write(to: url, options: .atomic)
        #endif
    }
}
