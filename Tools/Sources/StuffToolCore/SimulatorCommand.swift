import ArgumentParser

public struct SimulatorCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "./simulator",
        abstract: "Resolve this checkout's iOS Simulator by UDID.",
        discussion: """
        Each checkout owns a separate device. Progress and warnings go to
        stderr; resolve mode writes only the selected UDID to stdout.
        """,
    )

    @Option(help: "Simulator device name.")
    var device = "iPhone 17"

    @Option(help: "Simulator iOS version.")
    var os = "27.0"

    @Flag(name: .customLong("no-boot"), help: "Resolve without booting the device.")
    var noBoot = false

    @Flag(help: "Use an existing shared device instead of a checkout-owned one.")
    var shared = false

    @Flag(help: "List every checkout-owned and unowned Stuff simulator.")
    var list = false

    @Flag(help: "Delete stale registry entries and devices for deleted checkouts.")
    var prune = false

    @Flag(help: "Preview prune, delete, or recreate without changing anything.")
    var dryRun = false

    @Flag(help: "Delete this checkout's device.")
    var delete = false

    @Flag(help: "Delete and recreate this checkout's device.")
    var recreate = false

    public init() {}

    public mutating func run() async throws {
        let runtime = ToolRuntime()
        try await performPublicCommand(terminal: runtime.terminal) {
            let mode = try selectedMode()
            _ = try await runtime.simulatorService().run(
                SimulatorRequest(
                    device: device,
                    os: os,
                    boot: noBoot == false,
                    shared: shared,
                    dryRun: dryRun,
                    mode: mode,
                ),
            )
        }
    }

    private func selectedMode() throws -> SimulatorMode {
        let selected: [SimulatorMode] = [
            list ? .list : nil,
            prune ? .prune : nil,
            delete ? .delete : nil,
            recreate ? .recreate : nil,
        ].compactMap(\.self)
        guard selected.count <= 1 else {
            throw ToolFailure.message(
                "choose only one of --list, --prune, --delete, or --recreate",
            )
        }
        return selected.first ?? .resolve
    }
}
