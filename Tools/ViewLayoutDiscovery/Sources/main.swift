import Foundation

// One JSON object per file; paths arrive as arguments, never shell fragments.
do {
    var inventory: [String: [ViewCandidate]] = [:]
    for path in CommandLine.arguments.dropFirst() {
        inventory[path] = try discoverViews(
            source: String(contentsOfFile: path, encoding: .utf8),
            path: path,
        )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try FileHandle.standardOutput.write(encoder.encode(inventory))
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("error: view discovery failed: \(error)\n".utf8))
    exit(1)
}
