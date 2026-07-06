@_spi(Testing) import ForemanCore
import Foundation
import Testing

@MainActor
struct RepoSectionTests {
    /// Builds a repo with the given desired/favorite state *without* spawning a
    /// worker: `init` assigns `isEnabled` directly (only `startIfEnabled()` or
    /// the toggle's `didSet` would start one), so these stay pure.
    private func makeRepo(_ name: String, enabled: Bool, favorite: Bool) -> Repo {
        let root = URL(fileURLWithPath: "/tmp/RepoSectionTests/\(name)", isDirectory: true)
        return Repo(
            scanned: ScannedRepo(name: name, rootURL: root),
            isEnabled: enabled,
            isFavorite: favorite,
            options: .standard,
            provenance: nil,
            worker: Worker(
                name: name,
                workerDirectory: root,
                logDirectory: URL(fileURLWithPath: "/tmp/RepoSectionTests/logs", isDirectory: true),
                onStateChange: {},
            ),
            resolveExecutable: { URL(fileURLWithPath: "/usr/bin/true") },
            onPersistentChange: { _ in },
        )
    }

    private func names(_ sections: [RepoSection], _ kind: RepoSection.Kind) -> [String] {
        sections.first { $0.kind == kind }?.repos.map(\.name) ?? []
    }

    @Test func partitionsByEnabledWithTheEnabledSectionFirst() {
        let sections = RepoSection.sections(from: [
            makeRepo("Alpha", enabled: true, favorite: false),
            makeRepo("Beta", enabled: false, favorite: false),
        ])

        #expect(sections.map(\.kind) == [.enabled, .disabled])
        #expect(names(sections, .enabled) == ["Alpha"])
        #expect(names(sections, .disabled) == ["Beta"])
    }

    @Test func favoritesFloatToTheTopOfEachSectionKeepingOrderOtherwise() {
        // Input is name-sorted, as RepoDiscovery delivers it.
        let sections = RepoSection.sections(from: [
            makeRepo("Ada", enabled: true, favorite: false),
            makeRepo("Zoe", enabled: true, favorite: true),
            makeRepo("Bob", enabled: false, favorite: false),
            makeRepo("Xor", enabled: false, favorite: true),
        ])

        // The favorite leads each section; the rest keep alphabetical order.
        #expect(names(sections, .enabled) == ["Zoe", "Ada"])
        #expect(names(sections, .disabled) == ["Xor", "Bob"])
    }

    @Test func multipleFavoritesKeepTheirRelativeOrder() {
        let sections = RepoSection.sections(from: [
            makeRepo("Ann", enabled: true, favorite: true),
            makeRepo("Ben", enabled: true, favorite: false),
            makeRepo("Cat", enabled: true, favorite: true),
        ])

        #expect(names(sections, .enabled) == ["Ann", "Cat", "Ben"])
    }

    @Test func emptySectionsAreOmitted() {
        let allEnabled = RepoSection.sections(from: [
            makeRepo("Only", enabled: true, favorite: false),
        ])
        #expect(allEnabled.map(\.kind) == [.enabled])

        #expect(RepoSection.sections(from: []).isEmpty)
    }
}
