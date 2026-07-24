import ArgumentParser
import Foundation
import PortholeClientKit

/// `porthole devices` — browse Bonjour and list discovered + paired apps.
struct DevicesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "devices",
        abstract: "List discovered and paired apps.",
    )

    @Option(name: .long, help: "How long to browse, in seconds.")
    var timeout: Double = 3

    func run() async throws {
        let discovered = await browse(seconds: timeout)
        let paired = (try? CLIRuntime.makeClient().pairedApps()) ?? []
        let pairedBundles = Set(paired.map(\.bundleID))

        if paired.isEmpty, discovered.isEmpty {
            print("No apps found. Make sure a device app is advertising on the same network.")
            return
        }
        if !paired.isEmpty {
            print("Paired:")
            for app in paired {
                print("  \(app.appName) — \(app.bundleID) on \(app.deviceName)")
            }
        }
        if !discovered.isEmpty {
            print("Discovered:")
            for app in discovered {
                let mark = pairedBundles.contains(app.bundleID) ? " (paired)" : ""
                print("  \(app.appName) — \(app.bundleID) on \(app.deviceName)\(mark)")
            }
        }
    }
}

/// `porthole pair` — discover a device app and pair with it.
struct PairCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pair",
        abstract: "Pair with a device app.",
    )

    @OptionGroup var appOption: AppOption

    @Option(name: .long, help: "How long to browse for the app, in seconds.")
    var timeout: Double = 5

    func run() async throws {
        let discovered = await browse(seconds: timeout)
        guard !discovered.isEmpty else {
            throw ValidationError(
                "No advertising apps found. Is a device app running with Porthole enabled?",
            )
        }
        let target = try pick(from: discovered, selector: appOption.app)

        let pairingClient = PortholePairingClient()
        let paired = try await pairingClient.pair(with: target) {
            await promptForCode()
        }
        print("Paired with \(paired.appName) on \(paired.deviceName).")
    }

    private func pick(from apps: [DiscoveredApp], selector: String?) throws -> DiscoveredApp {
        if let selector {
            let lowered = selector.lowercased()
            let matches = apps.filter {
                $0.bundleID == selector || $0.appName.lowercased().contains(lowered) || $0
                    .deviceName.lowercased().contains(lowered)
            }
            guard let match = matches.first, matches.count == 1 else {
                throw ValidationError("--app did not uniquely match a discovered app.")
            }
            return match
        }
        guard apps.count == 1, let only = apps.first else {
            let names = apps.map(\.appName).joined(separator: ", ")
            throw ValidationError("Multiple apps found (\(names)); pass --app to choose one.")
        }
        return only
    }

    private func promptForCode() async -> String {
        FileHandle.standardError.write(Data("Code shown on device: ".utf8))
        return readLine(strippingNewline: true) ?? ""
    }
}

/// `porthole unpair` — forget a paired app locally.
struct UnpairCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unpair",
        abstract: "Forget a paired app.",
    )

    @OptionGroup var appOption: AppOption

    func run() async throws {
        let client = CLIRuntime.makeClient()
        let paired = try AppResolution.resolve(selector: appOption.app, from: client.pairedApps())
        try client.unpair(paired)
        print("Forgot \(paired.appName) on \(paired.deviceName).")
    }
}

/// Browses for `seconds` and returns the last-seen set of discovered apps.
func browse(seconds: Double) async -> [DiscoveredApp] {
    let browser = PortholeBrowser()
    let collected = LatestApps()
    let task = Task {
        for await apps in browser.discovered() {
            await collected.set(apps)
        }
    }
    try? await Task.sleep(for: .seconds(seconds))
    task.cancel()
    return await collected.get()
}

private actor LatestApps {
    private var apps: [DiscoveredApp] = []
    func set(_ newApps: [DiscoveredApp]) {
        apps = newApps
    }

    func get() -> [DiscoveredApp] {
        apps
    }
}
