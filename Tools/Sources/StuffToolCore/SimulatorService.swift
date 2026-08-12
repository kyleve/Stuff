import CryptoKit
import Foundation

public protocol SimulatorResolving: Sendable {
    func resolve(device: String, os: String, shared: Bool) async throws -> String
}

public enum SimulatorMode: String, Equatable, Sendable {
    case resolve
    case list
    case prune
    case delete
    case recreate
}

public struct SimulatorRequest: Equatable, Sendable {
    public let device: String
    public let os: String
    public let boot: Bool
    public let shared: Bool
    public let dryRun: Bool
    public let mode: SimulatorMode

    public init(
        device: String,
        os: String,
        boot: Bool,
        shared: Bool,
        dryRun: Bool,
        mode: SimulatorMode,
    ) {
        self.device = device
        self.os = os
        self.boot = boot
        self.shared = shared
        self.dryRun = dryRun
        self.mode = mode
    }
}

public struct SimulatorService: Sendable {
    private struct Identity {
        let checkout: URL
        let hash: String
        let ownedName: String
        let runtimeKey: String
    }

    private let runner: any CommandRunning
    private let fileSystem: any FileSystem
    private let clock: any ToolClock
    private let processInspector: any ProcessInspecting
    private let terminal: any Terminal
    private let repository: URL
    private let home: URL
    private let temporaryDirectory: URL
    private let processID: Int32
    private let decoder = JSONDecoder()

    public init(
        runner: any CommandRunning,
        fileSystem: any FileSystem,
        clock: any ToolClock,
        processInspector: any ProcessInspecting,
        terminal: any Terminal,
        repository: URL,
        home: URL,
        temporaryDirectory: URL,
        processID: Int32,
    ) {
        self.runner = runner
        self.fileSystem = fileSystem
        self.clock = clock
        self.processInspector = processInspector
        self.terminal = terminal
        self.repository = repository
        self.home = home
        self.temporaryDirectory = temporaryDirectory
        self.processID = processID
    }

    @discardableResult
    public func run(_ request: SimulatorRequest) async throws -> String? {
        try validate(request)
        let checkout = try await checkoutURL()
        let identity = makeIdentity(request: request, checkout: checkout)
        let registry = SimulatorRegistry(
            directory: home.appending(
                path: "Library/Application Support/Stuff/simulators",
                directoryHint: .isDirectory,
            ),
            fileSystem: fileSystem,
        )

        switch request.mode {
            case .list:
                try await list(registry: registry)
                return nil
            case .prune:
                try await prune(registry: registry, dryRun: request.dryRun)
                return nil
            case .delete:
                if request.dryRun {
                    try await deleteOwned(identity: identity, registry: registry, dryRun: true)
                    return nil
                }
                return try await withLock(identity: identity) { _ in
                    try await deleteOwned(
                        identity: identity,
                        registry: registry,
                        dryRun: false,
                    )
                    return nil
                }
            case .recreate:
                if request.dryRun {
                    try await deleteOwned(identity: identity, registry: registry, dryRun: true)
                    try await terminal.write(
                        "==> Would create and \(request.boot ? "boot" : "resolve") \(identity.ownedName)\n",
                        to: .standardError,
                    )
                    return nil
                }
                return try await withLock(identity: identity) { lock in
                    try await deleteOwned(identity: identity, registry: registry, dryRun: false)
                    return try await resolveOwned(
                        request: request,
                        identity: identity,
                        registry: registry,
                        lock: &lock,
                    )
                }
            case .resolve:
                if request.shared {
                    return try await resolveShared(request: request, identity: identity)
                } else {
                    return try await withLock(identity: identity) { lock in
                        try await resolveOwned(
                            request: request,
                            identity: identity,
                            registry: registry,
                            lock: &lock,
                        )
                    }
                }
        }
    }

    private func validate(_ request: SimulatorRequest) throws {
        guard request.device.isEmpty == false else {
            throw ToolFailure.message("--device requires a value")
        }
        guard request.os.isEmpty == false else {
            throw ToolFailure.message("--os requires a value")
        }
        if request.shared, request.mode != .resolve {
            throw ToolFailure.message(
                "--shared has no checkout of its own to \(request.mode.rawValue) (see ./simulator --help)",
            )
        }
        if request.dryRun, [.prune, .delete, .recreate].contains(request.mode) == false {
            throw ToolFailure.message(
                "--dry-run only applies to --prune, --delete, or --recreate (see ./simulator --help)",
            )
        }
    }

    private func checkoutURL() async throws -> URL {
        let result = try await runner.run(
            CommandInvocation(
                executable: "git",
                arguments: ["rev-parse", "--show-toplevel"],
                environment: [:],
                workingDirectory: repository,
                standardInput: [],
                output: .captured,
            ),
        )
        let path = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.succeeded, path.isEmpty == false else {
            return repository.resolvingSymlinksInPath()
        }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    private func makeIdentity(request: SimulatorRequest, checkout: URL) -> Identity {
        let hash = SHA256.hash(data: Data(checkout.path.utf8))
            .prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
        let name = [
            "Stuff",
            slug(checkout.lastPathComponent),
            hash,
            slug(request.device),
            slug(request.os),
        ].joined(separator: "-")
        return Identity(
            checkout: checkout,
            hash: hash,
            ownedName: name,
            runtimeKey: "com.apple.CoreSimulator.SimRuntime.iOS-\(request.os.replacing(".", with: "-"))",
        )
    }

    private func slug(_ value: String) -> String {
        var result = ""
        var previousWasSeparator = false
        for scalar in value.unicodeScalars {
            let allowed = scalar.properties.isAlphabetic || scalar.properties
                .numericType != nil || scalar == "."
            if allowed, scalar.isASCII {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if result.isEmpty == false, previousWasSeparator == false {
                result.append("-")
                previousWasSeparator = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func withLock(
        identity: Identity,
        operation: (inout DirectoryLock) async throws -> String?,
    ) async throws -> String? {
        var lock = DirectoryLock(
            directory: temporaryDirectory.appending(
                path: "stuff-simulator-\(identity.hash).lock",
                directoryHint: .isDirectory,
            ),
            processID: processID,
            fileSystem: fileSystem,
            clock: clock,
            processInspector: processInspector,
            warning: { message in
                try await terminal.write(message, to: .standardError)
            },
        )
        try await lock.acquire()
        do {
            let result = try await operation(&lock)
            try lock.release()
            return result
        } catch {
            try? lock.release()
            throw error
        }
    }

    private func resolveShared(
        request: SimulatorRequest,
        identity: Identity,
    ) async throws -> String {
        let devices = try await deviceList(availableOnly: true)
            .devices(runtime: identity.runtimeKey, named: request.device)
        guard case let .selected(udid, ambiguousCount) = SimulatorSelection.select(devices) else {
            try await terminal.write(
                "error: no available '\(request.device)' on the iOS \(request.os) runtime.\n",
                to: .standardError,
            )
            try await terminal.write("Available devices:\n", to: .standardError)
            try await runDiagnostic(["simctl", "list", "devices", "available"])
            throw ToolFailure.reported
        }
        return try await finishResolution(
            request: request,
            name: request.device,
            udid: udid,
            ambiguousCount: ambiguousCount,
        )
    }

    private func resolveOwned(
        request: SimulatorRequest,
        identity: Identity,
        registry: SimulatorRegistry,
        lock: inout DirectoryLock,
    ) async throws -> String {
        let devices = try await deviceList(availableOnly: true)
            .devices(runtime: identity.runtimeKey, named: identity.ownedName)
        let selection: SimulatorSelection = if devices.isEmpty {
            try await .selected(
                udid: createDevice(request: request, identity: identity),
                ambiguousCount: 1,
            )
        } else {
            SimulatorSelection.select(devices)
        }
        guard case let .selected(udid, ambiguousCount) = selection else {
            throw ToolFailure.message("could not resolve \(identity.ownedName)")
        }
        try registry.write(
            name: identity.ownedName,
            checkout: identity.checkout,
            udid: udid,
            device: request.device,
            os: request.os,
        )
        try lock.release()
        return try await finishResolution(
            request: request,
            name: identity.ownedName,
            udid: udid,
            ambiguousCount: ambiguousCount,
        )
    }

    private func finishResolution(
        request: SimulatorRequest,
        name: String,
        udid: String,
        ambiguousCount: Int,
    ) async throws -> String {
        if ambiguousCount > 1 {
            try await terminal.write(
                "warning: several '\(name)' devices on iOS \(request.os); using \(udid)\n",
                to: .standardError,
            )
        }
        if request.boot {
            try await terminal.write(
                "==> Booting \(name) (\(request.device) / iOS \(request.os), \(udid))\n",
                to: .standardError,
            )
            try await runStreamingToStandardError(["simctl", "bootstatus", udid, "-b"])
        }
        try await terminal.write("\(udid)\n", to: .standardOutput)
        return udid
    }

    private func createDevice(
        request: SimulatorRequest,
        identity: Identity,
    ) async throws -> String {
        let deviceTypes: SimctlDeviceTypes = try await decodeCommand([
            "simctl",
            "list",
            "devicetypes",
            "--json",
        ])
        guard let typeID = deviceTypes.devicetypes.first(where: { $0.name == request.device })?
            .identifier
        else {
            try await terminal.write(
                "error: no '\(request.device)' device type is installed.\nAvailable device types:\n",
                to: .standardError,
            )
            try await runDiagnostic(["simctl", "list", "devicetypes"])
            throw ToolFailure.reported
        }

        let runtimes: SimctlRuntimes = try await decodeCommand([
            "simctl",
            "list",
            "runtimes",
            "--json",
        ])
        guard runtimes.runtimes.contains(where: {
            $0.identifier == identity.runtimeKey && $0.isAvailable
        }) else {
            try await terminal.write(
                "error: the iOS \(request.os) runtime (\(identity.runtimeKey)) isn't installed or isn't usable.\nAvailable runtimes:\n",
                to: .standardError,
            )
            try await runDiagnostic(["simctl", "list", "runtimes"])
            throw ToolFailure.reported
        }

        try await terminal.write(
            "==> Creating \(identity.ownedName) (\(request.device) / iOS \(request.os)) for \(identity.checkout.path)\n",
            to: .standardError,
        )
        let result = try await checkedXcrun([
            "simctl",
            "create",
            identity.ownedName,
            typeID,
            identity.runtimeKey,
        ])
        let udid = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard udid.isEmpty == false else {
            throw ToolFailure.message(
                "simctl create returned no UDID for '\(identity.ownedName)'.",
            )
        }
        return udid
    }

    private func deleteOwned(
        identity: Identity,
        registry: SimulatorRegistry,
        dryRun: Bool,
    ) async throws {
        let devices = try await deviceList(availableOnly: false)
            .devices(runtime: identity.runtimeKey, named: identity.ownedName)
        for device in devices {
            let verb = dryRun ? "Would delete" : "Deleting"
            try await terminal.write(
                "==> \(verb) \(identity.ownedName) (\(device.udid))\n",
                to: .standardError,
            )
            if dryRun == false {
                try await runStreamingToStandardError(["simctl", "delete", device.udid])
            }
        }
        if dryRun == false {
            try registry.remove(name: identity.ownedName)
        }
        if devices.isEmpty {
            try await terminal.write(
                "==> No device for this checkout to delete\n",
                to: .standardError,
            )
        }
    }

    private func list(registry: SimulatorRegistry) async throws {
        let devices = try await deviceList(availableOnly: false)
        let stateByUDID = devices.allDevices.reduce(into: [String: String]()) { states, device in
            states[device.udid] = device.state
        }
        let entries = try registry.entries()
        let indexedUDIDs = Set(entries.compactMap(\.udid))
        var rows: [String] = []

        for entry in entries {
            let state = entry.udid.flatMap { stateByUDID[$0] } ?? "gone"
            let device = "\(entry.device ?? "") / iOS \(entry.os ?? "")"
            var checkout = entry.checkout?.path ?? "unknown (missing)"
            if let entryCheckout = entry.checkout,
               try fileSystem.kind(of: entryCheckout) != .directory
            {
                checkout += " (missing)"
            }
            rows.append(row(
                state: state,
                udid: entry.udid ?? "",
                device: device,
                checkout: checkout,
            ))
        }

        for device in devices.allDevices where device.name.hasPrefix("Stuff-") {
            guard indexedUDIDs.contains(device.udid) == false else { continue }
            rows.append(
                row(
                    state: device.state,
                    udid: device.udid,
                    device: device.name,
                    checkout: "unowned — no index entry",
                ),
            )
        }

        guard rows.isEmpty == false else {
            try await terminal.write(
                "No per-checkout simulators on this machine yet.\n",
                to: .standardError,
            )
            return
        }
        try await terminal.write(
            row(state: "STATE", udid: "UDID", device: "DEVICE", checkout: "CHECKOUT") + "\n",
            to: .standardOutput,
        )
        try await terminal.write(rows.joined(separator: "\n") + "\n", to: .standardOutput)
    }

    private func prune(registry: SimulatorRegistry, dryRun: Bool) async throws {
        let devices = try await deviceList(availableOnly: false)
        let knownUDIDs = Set(devices.allDevices.map(\.udid))
        let entries = try registry.entries()
        let indexedUDIDs = Set(entries.compactMap(\.udid))
        let deleteVerb = dryRun ? "Would delete" : "Deleting"
        let forgetVerb = dryRun ? "Would forget" : "Forgetting"
        var pruned = 0

        for entry in entries {
            let entryURL = registry.directory.appending(path: entry.name)
            guard let udid = entry.udid, udid.isEmpty == false else {
                try await terminal.write(
                    "==> \(forgetVerb) \(entry.name) — the entry records no UDID\n",
                    to: .standardError,
                )
                if dryRun == false { try fileSystem.removeItem(at: entryURL) }
                pruned += 1
                continue
            }
            guard knownUDIDs.contains(udid) else {
                try await terminal.write(
                    "==> \(forgetVerb) \(entry.name) — device \(udid) no longer exists\n",
                    to: .standardError,
                )
                if dryRun == false { try fileSystem.removeItem(at: entryURL) }
                pruned += 1
                continue
            }
            guard let checkout = entry.checkout else {
                try await terminal.write(
                    "==> Skipping \(entry.name) — the entry records no checkout\n",
                    to: .standardError,
                )
                continue
            }
            guard try fileSystem.kind(of: checkout) != .directory else { continue }
            guard try fileSystem.kind(of: checkout.deletingLastPathComponent()) == .directory else {
                try await terminal.write(
                    "==> Skipping \(entry.name) — \(checkout.path) is missing, but so is its parent (unmounted volume?)\n",
                    to: .standardError,
                )
                continue
            }
            try await terminal.write(
                "==> \(deleteVerb) \(entry.name) (\(udid)) — \(checkout.path) is gone\n",
                to: .standardError,
            )
            if dryRun == false {
                try await runStreamingToStandardError(["simctl", "delete", udid])
                try fileSystem.removeItem(at: entryURL)
            }
            pruned += 1
        }

        var unowned = 0
        for device in devices.allDevices where device.name.hasPrefix("Stuff-") {
            guard indexedUDIDs.contains(device.udid) == false else { continue }
            try await terminal.write(
                "==> Unowned: \(device.name) (\(device.udid)) — no checkout claims it.\n" +
                    "    A checkout that resolves to that name reclaims it on its next run;\n" +
                    "    otherwise remove it with: xcrun simctl delete \(device.udid)\n",
                to: .standardError,
            )
            unowned += 1
        }

        if dryRun, pruned > 0 {
            try await terminal.write("Dry run — nothing was deleted.\n", to: .standardError)
        } else if pruned == 0, unowned == 0 {
            try await terminal.write("Nothing to prune.\n", to: .standardError)
        } else if pruned == 0 {
            try await terminal.write(
                "Nothing to prune — the unowned devices above are left alone.\n",
                to: .standardError,
            )
        }
    }

    private func row(state: String, udid: String, device: String, checkout: String) -> String {
        "\(padded(state, width: 10))  \(padded(udid, width: 36))  \(padded(device, width: 22))  \(checkout)"
    }

    private func padded(_ value: String, width: Int) -> String {
        guard value.count < width else { return value }
        return value + String(repeating: " ", count: width - value.count)
    }

    private func deviceList(availableOnly: Bool) async throws -> SimctlDeviceList {
        var arguments = ["simctl", "list", "devices"]
        if availableOnly { arguments.append("available") }
        arguments.append("--json")
        return try await decodeCommand(arguments)
    }

    private func decodeCommand<Value: Decodable>(_ arguments: [String]) async throws -> Value {
        let result = try await checkedXcrun(arguments)
        do {
            return try decoder.decode(Value.self, from: Data(result.standardOutput))
        } catch {
            throw ToolFailure.message(
                "could not decode `xcrun \(arguments.joined(separator: " "))` JSON: \(error)",
            )
        }
    }

    private func checkedXcrun(_ arguments: [String]) async throws -> CommandResult {
        let result = try await runner.run(
            CommandInvocation(
                executable: "xcrun",
                arguments: arguments,
                environment: [:],
                workingDirectory: repository,
                standardInput: [],
                output: .captured,
            ),
        )
        guard result.succeeded else {
            try await terminal.write(result.standardError, to: .standardError)
            throw ToolFailure.exitCode(result.exitCode)
        }
        return result
    }

    private func runDiagnostic(_ arguments: [String]) async throws {
        let result = try await runner.run(
            CommandInvocation(
                executable: "xcrun",
                arguments: arguments,
                environment: [:],
                workingDirectory: repository,
                standardInput: [],
                output: .captured,
            ),
        )
        try await terminal.write(result.standardOutput, to: .standardError)
        try await terminal.write(result.standardError, to: .standardError)
    }

    private func runStreamingToStandardError(_ arguments: [String]) async throws {
        let result = try await runner.run(
            CommandInvocation(
                executable: "xcrun",
                arguments: arguments,
                environment: [:],
                workingDirectory: repository,
                standardInput: [],
                output: .captured,
            ),
            outputHandler: { _, bytes in
                try await terminal.write(bytes, to: .standardError)
            },
        )
        guard result.succeeded else { throw ToolFailure.exitCode(result.exitCode) }
    }
}

extension SimulatorService: SimulatorResolving {
    public func resolve(device: String, os: String, shared: Bool) async throws -> String {
        guard let udid = try await run(
            SimulatorRequest(
                device: device,
                os: os,
                boot: true,
                shared: shared,
                dryRun: false,
                mode: .resolve,
            ),
        ) else {
            throw ToolFailure.message("simulator resolution returned no UDID")
        }
        return udid
    }
}
