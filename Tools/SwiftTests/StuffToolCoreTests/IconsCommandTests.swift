import StuffToolCore
import Testing

struct IconsCommandTests {
    @Test func parserPreservesAddRemoveAndListInterfaces() throws {
        let add = try IconsCommand.parse([
            "--add",
            "art/ocean.png",
            "--name",
            "Ocean",
            "--id",
            "ocean",
            "--dark",
            "art/ocean-dark.png",
            "--tinted",
            "art/ocean-tinted.png",
            "--dry-run",
        ])
        #expect(try add.makeRequest() == .add(
            IconAddRequest(
                lightPath: "art/ocean.png",
                name: "Ocean",
                id: "ocean",
                darkPath: "art/ocean-dark.png",
                tintedPath: "art/ocean-tinted.png",
                dryRun: true,
            ),
        ))

        let remove = try IconsCommand.parse(["--remove", "ocean", "--dry-run"])
        #expect(try remove.makeRequest() == .remove(
            IconRemoveRequest(target: "ocean", dryRun: true),
        ))

        let list = try IconsCommand.parse(["--list"])
        #expect(try list.makeRequest() == .list)
    }

    @Test func requestValidationRejectsAmbiguousAndMisplacedOptions() throws {
        for arguments in [
            [],
            ["--list", "--remove", "pride"],
            ["--list", "--dry-run"],
            ["--remove", "pride", "--name", "Pride"],
            ["--add", ""],
            ["--add", "icon.png", "--id", ""],
        ] {
            let command = try IconsCommand.parse(arguments)
            #expect(throws: IconCatalogFailure.self) {
                _ = try command.makeRequest()
            }
        }
    }

    @Test func parserRejectsUnknownOptionsAndMissingValues() {
        #expect(throws: (any Error).self) {
            _ = try IconsCommand.parse(["--unknown"])
        }
        #expect(throws: (any Error).self) {
            _ = try IconsCommand.parse(["--add"])
        }
    }
}
