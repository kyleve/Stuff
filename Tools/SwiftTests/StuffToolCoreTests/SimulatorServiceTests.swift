import CryptoKit
import Foundation
import StuffToolCore
import Testing

struct SimulatorServiceTests {
    @Test func sharedResolutionWarnsAndSelectsTheFirstAmbiguousDevice() async throws {
        let root = try simulatorFixtureRoot()
        defer { removeTemporaryDirectory(root) }
        let checkout = root.appending(path: "repo", directoryHint: .isDirectory)
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: "\(checkout.path)\n"),
            .stub(standardOutput: deviceListJSON(devices: [
                ("iPhone 17", "FIRST", "Shutdown"),
                ("iPhone 17", "SECOND", "Booted"),
            ])),
        ])
        let terminal = MemoryTerminal()
        let service = makeService(root: root, runner: runner, terminal: terminal)

        try await service.run(
            SimulatorRequest(
                device: "iPhone 17",
                os: "27.0",
                boot: false,
                shared: true,
                dryRun: false,
                mode: .resolve,
            ),
        )

        #expect(await terminal.standardOutputText == "FIRST\n")
        #expect(await terminal.standardErrorText.contains("warning: several 'iPhone 17'"))
        #expect(await runner.invocations.count == 2)
    }

    @Test func pruneReportsButNeverDeletesAnUnownedDevice() async throws {
        let root = try simulatorFixtureRoot()
        defer { removeTemporaryDirectory(root) }
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: "\(root.path)\n"),
            .stub(standardOutput: deviceListJSON(devices: [
                ("Stuff-orphan", "ORPHAN", "Shutdown"),
            ])),
        ])
        let terminal = MemoryTerminal()
        let service = makeService(root: root, runner: runner, terminal: terminal)

        try await service.run(
            SimulatorRequest(
                device: "iPhone 17",
                os: "27.0",
                boot: true,
                shared: false,
                dryRun: false,
                mode: .prune,
            ),
        )

        #expect(await runner.invocations.count == 2)
        #expect(await terminal.standardErrorText.contains("Unowned: Stuff-orphan (ORPHAN)"))
        #expect(await terminal.standardErrorText.contains("left alone"))
    }

    @Test func interruptedCreationReleasesTheCheckoutLock() async throws {
        let root = try simulatorFixtureRoot()
        defer { removeTemporaryDirectory(root) }
        let checkout = root.appending(path: "repo", directoryHint: .isDirectory)
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: "\(checkout.path)\n"),
            .stub(standardOutput: deviceListJSON(devices: [])),
            .stub(standardOutput: """
            {"devicetypes":[{"name":"iPhone 17","identifier":"DEVICE-TYPE"}]}
            """),
            .stub(standardOutput: """
            {"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","isAvailable":true}]}
            """),
            .stub(exitCode: 23, standardError: "create failed\n"),
        ])
        let terminal = MemoryTerminal()
        let service = makeService(root: root, runner: runner, terminal: terminal)

        do {
            try await service.run(
                SimulatorRequest(
                    device: "iPhone 17",
                    os: "27.0",
                    boot: true,
                    shared: false,
                    dryRun: false,
                    mode: .resolve,
                ),
            )
            Issue.record("expected creation to fail")
        } catch ToolFailure.exitCode(23) {
            // Expected.
        }

        let temporary = root.appending(path: "tmp", directoryHint: .isDirectory)
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporary.path).isEmpty)
        #expect(await terminal.standardErrorText.contains("create failed"))
    }

    @Test func deleteTargetsOnlyTheExactCheckoutOwnedName() async throws {
        let root = try simulatorFixtureRoot()
        defer { removeTemporaryDirectory(root) }
        let checkout = root.appending(path: "repo", directoryHint: .isDirectory)
        let ownedName = simulatorName(checkout: checkout, device: "iPhone 17", os: "27.0")
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: "\(checkout.path)\n"),
            .stub(standardOutput: deviceListJSON(devices: [
                (ownedName, "EXACT", "Shutdown"),
                (ownedName + "-copy", "NEARBY", "Shutdown"),
                ("Stuff-orphan", "ORPHAN", "Shutdown"),
            ])),
            .stub(),
        ])
        let terminal = MemoryTerminal()
        let registry = SimulatorRegistry(
            directory: registryDirectory(root: root),
            fileSystem: FoundationFileSystem(),
        )
        try registry.write(
            name: ownedName,
            checkout: checkout,
            udid: "EXACT",
            device: "iPhone 17",
            os: "27.0",
        )
        let service = makeService(root: root, runner: runner, terminal: terminal)

        try await service.run(
            SimulatorRequest(
                device: "iPhone 17",
                os: "27.0",
                boot: true,
                shared: false,
                dryRun: false,
                mode: .delete,
            ),
        )

        let invocations = await runner.invocations
        #expect(invocations.count == 3)
        #expect(invocations[2].arguments == ["simctl", "delete", "EXACT"])
        #expect(try registry.entries().isEmpty)
        #expect(await terminal.standardErrorText.contains("(EXACT)"))
        #expect(await terminal.standardErrorText.contains("NEARBY") == false)
    }

    @Test func deleteTargetsOnlyTheRequestedRuntime() async throws {
        let root = try simulatorFixtureRoot()
        defer { removeTemporaryDirectory(root) }
        let checkout = root.appending(path: "repo", directoryHint: .isDirectory)
        let ownedName = simulatorName(checkout: checkout, device: "iPhone 17", os: "27.0")
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: "\(checkout.path)\n"),
            .stub(standardOutput: deviceListJSON(runtimeDevices: [
                "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                    (ownedName, "REQUESTED-RUNTIME", "Shutdown"),
                ],
                "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
                    (ownedName, "OTHER-RUNTIME", "Shutdown"),
                ],
            ])),
            .stub(),
        ])
        let terminal = MemoryTerminal()
        let registry = SimulatorRegistry(
            directory: registryDirectory(root: root),
            fileSystem: FoundationFileSystem(),
        )
        try registry.write(
            name: ownedName,
            checkout: checkout,
            udid: "REQUESTED-RUNTIME",
            device: "iPhone 17",
            os: "27.0",
        )
        let service = makeService(root: root, runner: runner, terminal: terminal)

        try await service.run(
            SimulatorRequest(
                device: "iPhone 17",
                os: "27.0",
                boot: true,
                shared: false,
                dryRun: false,
                mode: .delete,
            ),
        )

        let invocations = await runner.invocations
        #expect(invocations.count == 3)
        #expect(invocations[2].arguments == ["simctl", "delete", "REQUESTED-RUNTIME"])
        #expect(await terminal.standardErrorText.contains("OTHER-RUNTIME") == false)
    }

    @Test func deleteDryRunPreservesTheDeviceAndRegistry() async throws {
        let root = try simulatorFixtureRoot()
        defer { removeTemporaryDirectory(root) }
        let checkout = root.appending(path: "repo", directoryHint: .isDirectory)
        let ownedName = simulatorName(checkout: checkout, device: "iPhone 17", os: "27.0")
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: "\(checkout.path)\n"),
            .stub(standardOutput: deviceListJSON(devices: [
                (ownedName, "EXACT", "Shutdown"),
            ])),
        ])
        let terminal = MemoryTerminal()
        let registry = SimulatorRegistry(
            directory: registryDirectory(root: root),
            fileSystem: FoundationFileSystem(),
        )
        try registry.write(
            name: ownedName,
            checkout: checkout,
            udid: "EXACT",
            device: "iPhone 17",
            os: "27.0",
        )
        let lock = root.appending(
            path: "tmp/stuff-simulator-\(simulatorHash(checkout: checkout)).lock",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: true)
        try Data("99\n".utf8).write(to: lock.appending(path: "pid"))
        let service = makeService(
            root: root,
            runner: runner,
            terminal: terminal,
            runningProcessIDs: [99],
        )

        try await service.run(
            SimulatorRequest(
                device: "iPhone 17",
                os: "27.0",
                boot: true,
                shared: false,
                dryRun: true,
                mode: .delete,
            ),
        )

        #expect(await runner.invocations.count == 2)
        #expect(try registry.entries().count == 1)
        #expect(FileManager.default.fileExists(atPath: lock.path))
        #expect(await terminal.standardErrorText.contains("Would delete"))
    }

    @Test func bootFailurePreservesSimctlExitStatus() async throws {
        let root = try simulatorFixtureRoot()
        defer { removeTemporaryDirectory(root) }
        let checkout = root.appending(path: "repo", directoryHint: .isDirectory)
        let runner = FakeCommandRunner(responses: [
            .stub(standardOutput: "\(checkout.path)\n"),
            .stub(standardOutput: deviceListJSON(devices: [
                ("iPhone 17", "SHARED", "Shutdown"),
            ])),
            .stub(exitCode: 42, standardError: "boot failed\n"),
        ])
        let terminal = MemoryTerminal()
        let service = makeService(root: root, runner: runner, terminal: terminal)

        do {
            try await service.run(
                SimulatorRequest(
                    device: "iPhone 17",
                    os: "27.0",
                    boot: true,
                    shared: true,
                    dryRun: false,
                    mode: .resolve,
                ),
            )
            Issue.record("expected booting to fail")
        } catch ToolFailure.exitCode(42) {
            // Expected.
        }

        #expect(await terminal.standardErrorText.contains("boot failed"))
    }
}

private func simulatorFixtureRoot() throws -> URL {
    let root = try makeTemporaryDirectory()
    try FileManager.default.createDirectory(
        at: root.appending(path: "tmp", directoryHint: .isDirectory),
        withIntermediateDirectories: true,
    )
    return root
}

private func makeService(
    root: URL,
    runner: FakeCommandRunner,
    terminal: MemoryTerminal,
    runningProcessIDs: Set<Int32> = [],
) -> SimulatorService {
    SimulatorService(
        runner: runner,
        fileSystem: FoundationFileSystem(),
        clock: ImmediateClock(),
        processInspector: StubProcessInspector(runningProcessIDs: runningProcessIDs),
        terminal: terminal,
        repository: root,
        home: root.appending(path: "home", directoryHint: .isDirectory),
        temporaryDirectory: root.appending(path: "tmp", directoryHint: .isDirectory),
        processID: 42,
    )
}

private func registryDirectory(root: URL) -> URL {
    root.appending(
        path: "home/Library/Application Support/Stuff/simulators",
        directoryHint: .isDirectory,
    )
}

private func deviceListJSON(
    devices: [(name: String, udid: String, state: String)],
) -> String {
    deviceListJSON(runtimeDevices: [
        "com.apple.CoreSimulator.SimRuntime.iOS-27-0": devices,
    ])
}

private func deviceListJSON(
    runtimeDevices: [String: [(name: String, udid: String, state: String)]],
) -> String {
    let values = runtimeDevices.mapValues { devices in
        devices.map { device in
            ["name": device.name, "udid": device.udid, "state": device.state]
        }
    }
    let object: [String: Any] = ["devices": values]
    do {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    } catch {
        preconditionFailure("invalid simulator test fixture: \(error)")
    }
}

private func simulatorName(checkout: URL, device: String, os: String) -> String {
    let hash = simulatorHash(checkout: checkout)
    func slug(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "-")
    }
    return "Stuff-\(slug(checkout.lastPathComponent))-\(hash)-\(slug(device))-\(slug(os))"
}

private func simulatorHash(checkout: URL) -> String {
    SHA256.hash(data: Data(checkout.path.utf8))
        .prefix(4)
        .map { String(format: "%02x", $0) }
        .joined()
}
