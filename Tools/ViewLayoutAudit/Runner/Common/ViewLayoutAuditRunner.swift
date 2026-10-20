import Foundation

/// Writes metatype measurements and exits without a production app lifecycle.
@MainActor
enum ViewLayoutAuditRunner {
    static func run(records: [String]) throws {
        #if !VIEW_LAYOUT_AUDIT
            #error("The measurement runner requires VIEW_LAYOUT_AUDIT in every module")
        #endif
        #if arch(arm64)
            let architecture = "arm64"
        #elseif arch(x86_64)
            let architecture = "x86_64"
        #else
            #error("Register the new audit architecture before using its measurements")
        #endif
        let build = try Build(
            configuration: setting("Configuration"),
            platform: setting("Platform") == "macosx" ? "macOS" : "iOSSimulator",
            architecture: architecture,
            xcode: setting("Xcode"),
            commit: setting("Commit"),
            inputHash: setting("InputHash"),
            optimization: setting("Optimization"),
        )
        let buildJSON = try String(decoding: JSONEncoder().encode(build), as: UTF8.self)
        let report = "{\"build\":\(buildJSON),\"samples\":[\(records.joined(separator: ","))]}"
        guard let output = ProcessInfo.processInfo.environment["VIEW_LAYOUT_AUDIT_OUTPUT"] else {
            throw Failure.missingBuildSetting("VIEW_LAYOUT_AUDIT_OUTPUT")
        }
        try Data(report.utf8).write(to: URL(fileURLWithPath: output), options: .atomic)
        FileHandle.standardError.write(Data("VIEW_LAYOUT_AUDIT_COMPLETE\n".utf8))
        exit(0)
    }

    private struct Build: Encodable {
        let configuration: String
        let platform: String
        let architecture: String
        let xcode: String
        let commit: String
        let inputHash: String
        let optimization: String
    }

    private enum Failure: Error {
        case missingBuildSetting(String)
    }

    private static func setting(_ key: String) throws -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LayoutAudit\(key)") as? String,
              !value.isEmpty, !value.contains("$(")
        else { throw Failure.missingBuildSetting(key) }
        return value
    }
}
