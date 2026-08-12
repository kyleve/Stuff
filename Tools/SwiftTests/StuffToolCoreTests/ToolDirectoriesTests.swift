import Foundation
import StuffToolCore
import Testing

struct ToolDirectoriesTests {
    @Test func environmentOverridesFoundationDirectories() {
        let directories = ToolDirectories(
            environment: [
                "HOME": "/private/tmp/stuff-home",
                "TMPDIR": "/private/tmp/stuff-temporary",
            ],
            homeFallback: URL(filePath: "/Users/fallback", directoryHint: .isDirectory),
            temporaryFallback: URL(filePath: "/tmp", directoryHint: .isDirectory),
        )

        #expect(directories.home.path == "/private/tmp/stuff-home")
        #expect(directories.temporary.path == "/private/tmp/stuff-temporary")
    }

    @Test func emptyOverridesUseFoundationDirectories() {
        let home = URL(filePath: "/Users/fallback", directoryHint: .isDirectory)
        let temporary = URL(filePath: "/tmp", directoryHint: .isDirectory)
        let directories = ToolDirectories(
            environment: ["HOME": "", "TMPDIR": ""],
            homeFallback: home,
            temporaryFallback: temporary,
        )

        #expect(directories.home == home)
        #expect(directories.temporary == temporary)
    }
}
