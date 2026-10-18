import Foundation

@main
struct TestImpactIndex {
    static func main() {
        do {
            let request = try JSONDecoder().decode(
                IndexRequest.self,
                from: FileHandle.standardInput.readDataToEndOfFile(),
            )
            let files = try IndexCollector().collect(request)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileHandle.standardOutput.write(encoder.encode(files))
        } catch {
            FileHandle.standardError.write(Data("test-impact-index: \(error)\n".utf8))
            exit(1)
        }
    }
}
