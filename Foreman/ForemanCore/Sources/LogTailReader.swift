import Foundation

/// Reads the end of a (potentially large, still-growing) worker log file for
/// display, without loading the whole file.
public enum LogTailReader {
    /// Returns up to `maxBytes` from the end of the file at `url`, decoded
    /// as UTF-8 (lossily, so cutting a multi-byte character can't fail).
    /// When the read is truncated, the partial first line is dropped so the
    /// result starts on a line boundary (unless the chunk contains no
    /// newline at all, in which case it's returned as-is).
    ///
    /// Returns `nil` when no file exists yet — a worker that has never
    /// started is a legitimate state, not an error. Other I/O failures throw.
    public static func tail(of url: URL, maxBytes: Int) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        // Closing a read-only handle can't lose data; nothing actionable to
        // report if it fails.
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()

        let text = String(decoding: data, as: UTF8.self)
        guard offset > 0, let newline = text.firstIndex(of: "\n") else {
            return text
        }
        return String(text[text.index(after: newline)...])
    }
}
