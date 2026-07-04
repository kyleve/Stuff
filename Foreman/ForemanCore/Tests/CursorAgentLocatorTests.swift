@_spi(Testing) import ForemanCore
import Foundation
import Testing

struct CursorAgentLocatorTests {
    @Test func validExplicitPathWins() throws {
        let directory = try makeTemporaryDirectory()
        let explicit = try makeStubExecutable(in: directory, script: "#!/bin/sh\nexit 0\n")
        let locator = CursorAgentLocator(searchPaths: [])

        #expect(try locator.locate(explicit: explicit) == explicit)
    }

    @Test func staleExplicitPathThrowsInsteadOfFallingBack() throws {
        let directory = try makeTemporaryDirectory()
        // A fallback the locator could otherwise find.
        let fallback = try makeStubExecutable(in: directory, script: "#!/bin/sh\nexit 0\n")
        let locator = CursorAgentLocator(searchPaths: [fallback.path])
        let missing = directory.appendingPathComponent("gone")

        #expect(throws: CursorAgentLocator.NotFoundError(searchedPaths: [missing.path])) {
            try locator.locate(explicit: missing)
        }
    }

    @Test func searchPathsAreCheckedInOrder() throws {
        let directory = try makeTemporaryDirectory()
        let second = try makeStubExecutable(
            in: directory,
            named: "second",
            script: "#!/bin/sh\nexit 0\n",
        )
        let missingFirst = directory.appendingPathComponent("first").path
        let locator = CursorAgentLocator(searchPaths: [missingFirst, second.path])

        #expect(try locator.locate(explicit: nil) == second)
    }

    @Test func nonExecutableFilesAreSkipped() throws {
        let directory = try makeTemporaryDirectory()
        let plainFile = directory.appendingPathComponent("not-executable")
        try Data("#!/bin/sh\n".utf8).write(to: plainFile)
        let locator = CursorAgentLocator(searchPaths: [plainFile.path])

        #expect(throws: CursorAgentLocator.NotFoundError(searchedPaths: [plainFile.path])) {
            try locator.locate(explicit: nil)
        }
    }
}
