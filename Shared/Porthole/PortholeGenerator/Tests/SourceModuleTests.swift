import Foundation
@testable import PortholeGenerator
import Testing

struct SourceModuleTests {
    @Test func sourceArchivePreservesExactContent() throws {
        let files = [SourceFile(
            path: "Sources/File.swift",
            content: "// é\nprivate let text = \"\\(1)\"\n",
        )]
        let roundTrip = try JSONDecoder().decode(
            [SourceFile].self,
            from: JSONEncoder().encode(files),
        )
        #expect(roundTrip.first?.path == files.first?.path)
        #expect(roundTrip.first?.content == files.first?.content)
        #expect(roundTrip.first?.sha256 == files.first?.sha256)
        #expect(SourceFile(path: "empty", content: "")
            .sha256 == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
}
