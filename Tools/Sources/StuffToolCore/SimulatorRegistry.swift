import Foundation

public struct SimulatorRegistryEntry: Equatable, Sendable {
    public let name: String
    public let checkout: URL?
    public let udid: String?
    public let device: String?
    public let os: String?

    public init(
        name: String,
        checkout: URL?,
        udid: String?,
        device: String?,
        os: String?,
    ) {
        self.name = name
        self.checkout = checkout
        self.udid = udid
        self.device = device
        self.os = os
    }
}

public struct SimulatorRegistry: Sendable {
    public let directory: URL
    private let fileSystem: any FileSystem

    public init(directory: URL, fileSystem: any FileSystem) {
        self.directory = directory
        self.fileSystem = fileSystem
    }

    public func entries() throws -> [SimulatorRegistryEntry] {
        guard try fileSystem.kind(of: directory) == .directory else { return [] }
        return try fileSystem.contents(of: directory)
            .filter { try fileSystem.kind(of: $0) == .file }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map(readEntry)
    }

    public func write(
        name: String,
        checkout: URL,
        udid: String,
        device: String,
        os: String,
    ) throws {
        try fileSystem.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = """
        checkout=\(checkout.path)
        udid=\(udid)
        device=\(device)
        os=\(os)

        """
        try fileSystem.write(
            Data(text.utf8),
            to: directory.appending(path: name),
            atomically: true,
        )
    }

    public func remove(name: String) throws {
        let url = directory.appending(path: name)
        guard try fileSystem.kind(of: url) != .missing else { return }
        try fileSystem.removeItem(at: url)
    }

    private func readEntry(_ url: URL) throws -> SimulatorRegistryEntry {
        let text = try String(decoding: fileSystem.read(url), as: UTF8.self)
        let fields = text.split(separator: "\n").reduce(into: [String: String]()) { result, line in
            let field = String(line)
            guard let separator = field.firstIndex(of: "=") else { return }
            result[String(field[..<separator])] = String(field[field.index(after: separator)...])
        }
        return SimulatorRegistryEntry(
            name: url.lastPathComponent,
            checkout: fields["checkout"].map { URL(filePath: $0, directoryHint: .isDirectory) },
            udid: fields["udid"],
            device: fields["device"],
            os: fields["os"],
        )
    }
}
