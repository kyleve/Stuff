import CryptoKit
import Darwin
import Foundation
import PortholeCore
@testable import PortholeRuntime
import Testing

struct PortholeFileAccessTests {
    @Test func writesRequireTheObservedVersionAndEnforceReadLimits() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
        }
        let access = PortholeFileAccess(root: directory, components: ["note.txt"], maximumBytes: 20)
        let first = Data("original".utf8)
        let second = Data("replacement".utf8)
        try access.write(first, expected: nil, hash: digest)
        #expect(try access.read() == first)
        #expect(throws: PortholeError.operationConflict) { try access.write(
            second,
            expected: nil,
            hash: digest,
        ) }
        #expect(throws: PortholeError.operationConflict) { try access.write(
            second,
            expected: digest(second),
            hash: digest,
        ) }
        #expect(try access.read() == first)
        try access.write(second, expected: digest(first), hash: digest)
        #expect(try access.read() == second)
        let small = PortholeFileAccess(root: directory, components: ["note.txt"], maximumBytes: 4)
        #expect(throws: PortholeError.capacityExceeded) { try small.read() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["note.txt"])
    }

    @Test func renamedParentCannotRedirectAnOpenOperationThroughASymlink() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
        }
        let original = directory.appending(path: "inside")
        let outside = directory.appending(path: "outside")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let access = PortholeFileAccess(
            root: directory,
            components: ["inside", "new.txt"],
            maximumBytes: 20,
        )
        try access.withParent { descriptor, leaf in
            try FileManager.default.moveItem(
                at: original,
                to: directory.appending(path: "retained"),
            )
            try FileManager.default.createSymbolicLink(at: original, withDestinationURL: outside)
            let file = try openat(
                descriptor,
                #require(leaf),
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                0o600,
            )
            #expect(file >= 0)
            if file >= 0 { close(file) }
        }
        #expect(FileManager.default
            .fileExists(atPath: directory.appending(path: "retained/new.txt").path))
        #expect(!FileManager.default.fileExists(atPath: outside.appending(path: "new.txt").path))
        #expect(throws: PortholeError.self) { try access.validate() }
    }

    @Test func directoryEnumerationIsBoundedAndDoesNotFollowLeafLinks() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
        }
        try Data("text".utf8).write(to: directory.appending(path: "a.txt"))
        try FileManager.default.createSymbolicLink(
            at: directory.appending(path: "b.txt"),
            withDestinationURL: directory.appending(path: "a.txt"),
        )
        let access = PortholeFileAccess(root: directory, components: [], maximumBytes: 20)
        let entries = try access.entries(maximumCount: 2)
        #expect(entries.map(\.name) == ["a.txt", "b.txt"])
        #expect(entries[1].isSymbolicLink)
        #expect(throws: PortholeError.capacityExceeded) { try access.entries(maximumCount: 1) }
        let link = PortholeFileAccess(root: directory, components: ["b.txt"], maximumBytes: 20)
        #expect(throws: PortholeError.self) { try link.read() }
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
