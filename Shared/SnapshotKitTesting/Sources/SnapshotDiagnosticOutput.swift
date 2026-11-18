import Foundation

/// Submit the complete UTF-8 record and newline together. Swift print can split
/// a long record across buffered writes that interleave with native app logs.
/// Downstream transport can still fail; collectors must validate completeness.
func writeSnapshotDiagnostic(_ line: String) {
    do {
        try FileHandle.standardOutput.write(contentsOf: Data((line + "\n").utf8))
    } catch {
        fatalError("Could not write snapshot diagnostic: \(error)")
    }
}
