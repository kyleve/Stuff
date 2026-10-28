import Foundation
import JournalKit

/// A fresh journal directory in the temporary directory; callers clean up
/// via `defer { try? FileManager.default.removeItem(at: url) }`.
func makeJournalDirectory() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("journalkit-tests-\(UUID().uuidString)", isDirectory: true)
}

func payload(_ text: String) -> Data {
    Data(text.utf8)
}

func texts(_ payloads: [Data]) -> [String] {
    payloads.map { String(decoding: $0, as: UTF8.self) }
}
