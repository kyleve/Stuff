import Foundation

struct JSONFileStore<Record: Codable & Sendable> {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(defaultValue: Record) -> Record {
        guard let data = try? Data(contentsOf: fileURL) else {
            return defaultValue
        }

        return (try? decoder.decode(Record.self, from: data)) ?? defaultValue
    }

    func save(_ record: Record) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil,
            )
            let data = try encoder.encode(record)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Failed to save JSON store at \(fileURL.path): \(error)")
        }
    }
}
