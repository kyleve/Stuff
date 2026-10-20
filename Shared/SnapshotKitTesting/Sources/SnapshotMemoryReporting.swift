import Foundation

/// Samples host memory after a complete reference comparison, including cutsheet assembly.
/// This channel does not count captures: a cutsheet has several panel timing lines.
@MainActor
@_spi(Testing) public enum SnapshotMemoryReporting {
    /// Only the assertion pipeline emits this channel. Wire-format tests use `line`.
    public static func report(reference: URL) {
        do {
            if let json = try line(
                reference: reference,
                isEnabled: SnapshotCaptureTiming.isEnabledByEnvironment,
            ) {
                print("SNAPSHOT_MEMORY \(json)")
            }
        } catch {
            print("SNAPSHOT_MEMORY_ERROR \(reference.path): \(error)")
        }
    }

    /// Returns a payload without printing or changing progress counters.
    public static func line(reference: URL, isEnabled: Bool) throws -> String? {
        guard isEnabled else { return nil }
        let sample = try Sample(
            reference: reference,
            processID: ProcessInfo.processInfo.processIdentifier,
            memory: SnapshotProcessMemory.current(),
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try String(decoding: encoder.encode(sample), as: UTF8.self)
    }

    private struct Sample: Encodable {
        let reference: URL
        let processID: Int32
        let memory: SnapshotProcessMemory
    }
}
