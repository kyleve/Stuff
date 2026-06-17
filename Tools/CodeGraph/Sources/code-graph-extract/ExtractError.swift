import Foundation

enum ExtractError: Error, CustomStringConvertible {
    case libIndexStoreNotFound(String)
    case indexStoreNotFound(String)
    case missingWorkspace(String)
    case processFailed(command: String, status: Int32, output: String)

    var description: String {
        switch self {
            case let .libIndexStoreNotFound(path):
                "Could not find libIndexStore.dylib at \(path). Pass --toolchain-lib to override."
            case let .indexStoreNotFound(path):
                "No index store found at \(path). Build first, or pass --index-store-path."
            case let .missingWorkspace(path):
                "Expected an Xcode workspace at \(path). Run `tuist generate` first."
            case let .processFailed(command, status, output):
                "Command failed (exit \(status)): \(command)\n\(output)"
        }
    }
}
