import Foundation
import StuffToolCore
import Testing

struct StringCatalogNormalizerTests {
    @Test func lintReportsWithoutWriting() throws {
        try withTemporaryDirectory { directory in
            let catalog = directory.appending(path: "Localizable.xcstrings")
            let original = Data("{\"sourceLanguage\":\"en\",\"strings\":{}}\n".utf8)
            try original.write(to: catalog)
            var reports: [String] = []

            let offenders = try StringCatalogNormalizer().normalize(
                [catalog],
                lintOnly: true,
                displayRoot: directory,
            ) { reports.append($0) }

            #expect(offenders == [catalog])
            #expect(try Data(contentsOf: catalog) == original)
            #expect(reports == ["not normalized: Localizable.xcstrings"])
        }
    }

    @Test func normalizationWritesAtomicallyAndPreservesContent() throws {
        try withTemporaryDirectory { directory in
            let catalog = directory.appending(path: "Localizable.xcstrings")
            try Data("{\"sourceLanguage\":\"en\",\"strings\":{}}\n".utf8).write(to: catalog)

            let offenders = try StringCatalogNormalizer().normalize(
                [catalog],
                lintOnly: false,
                displayRoot: directory,
            ) { _ in }
            let data = try Data(contentsOf: catalog)
            let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            #expect(offenders == [catalog])
            #expect(decoded?["sourceLanguage"] as? String == "en")
            #expect(data.last != 10)
        }
    }

    @Test func reportsPathsRelativeToAnExplicitDisplayRoot() throws {
        try withTemporaryDirectory { directory in
            let repository = directory.appending(path: "repository", directoryHint: .isDirectory)
            let catalog = repository.appending(path: "Sources/Localizable.xcstrings")
            try FileManager.default.createDirectory(
                at: catalog.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try Data("{\"sourceLanguage\":\"en\",\"strings\":{}}\n".utf8).write(to: catalog)
            var reports: [String] = []

            _ = try StringCatalogNormalizer().normalize(
                [catalog],
                lintOnly: true,
                displayRoot: repository,
            ) { reports.append($0) }

            #expect(reports == ["not normalized: Sources/Localizable.xcstrings"])
        }
    }

    @Test func discoverySkipsHiddenAndBuildDirectories() throws {
        try withTemporaryDirectory { directory in
            let visible = directory.appending(path: "Sources/Localizable.xcstrings")
            let hidden = directory.appending(path: ".cache/Hidden.xcstrings")
            let derived = directory.appending(path: "Derived/Generated.xcstrings")
            try FileManager.default.createDirectory(
                at: visible.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try FileManager.default.createDirectory(
                at: hidden.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try FileManager.default.createDirectory(
                at: derived.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            for url in [visible, hidden, derived] {
                try Data("{}".utf8).write(to: url)
            }

            let catalogs = try StringCatalogNormalizer().catalogs(under: directory)

            #expect(catalogs.count == 1)
            #expect(catalogs[0].path.hasSuffix("/Sources/Localizable.xcstrings"))
        }
    }
}

private func withTemporaryDirectory(
    _ body: (URL) throws -> Void,
) throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "StuffToolTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        .resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}
