import Foundation

/// Resolves build labels once per generator invocation and shares them with source-only modules.
enum BuildMetadataResolver {
    static func resolve(
        environment: [String: String],
        compilerVersion: () throws -> String,
    ) throws -> SourceModule.BuildMetadata {
        let explicitToolchain = environment["PORTHOLE_TOOLCHAIN_ID"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let toolchain = try explicitToolchain.flatMap { $0.isEmpty ? nil : $0 } ?? compilerVersion()
        guard !toolchain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeneratorError
                .arguments("The Swift compiler returned an empty version identifier.")
        }
        let configuration = [
            environment["PORTHOLE_BUILD_CONFIGURATION"],
            environment["CONFIGURATION"],
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty } ?? "unknown"
        return .init(configuration: configuration, toolchain: toolchain)
    }

    static func installedCompilerVersion() throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swiftc", "--version"]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw GeneratorError.arguments("Could not read the Swift compiler version: \(output)")
        }
        return output
    }
}
