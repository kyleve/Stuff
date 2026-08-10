import Foundation
import StuffToolCore
import Testing

struct SimulatorRegistryTests {
    @Test func writesReadsAndRemovesTheLegacyRegistryFormat() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let directory = root.appending(path: "registry", directoryHint: .isDirectory)
        let registry = SimulatorRegistry(
            directory: directory,
            fileSystem: FoundationFileSystem(),
        )

        try registry.write(
            name: "Stuff-one",
            checkout: URL(filePath: "/tmp/Stuff One", directoryHint: .isDirectory),
            udid: "UDID",
            device: "iPhone 17",
            os: "27.0",
        )

        #expect(try registry.entries() == [
            SimulatorRegistryEntry(
                name: "Stuff-one",
                checkout: URL(filePath: "/tmp/Stuff One", directoryHint: .isDirectory),
                udid: "UDID",
                device: "iPhone 17",
                os: "27.0",
            ),
        ])

        try registry.remove(name: "Stuff-one")
        #expect(try registry.entries().isEmpty)
    }
}
