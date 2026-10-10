import Foundation
import PeriscopeCore

@LogScope("ErrorFixture")
enum LogErrorTestLog {
    @LogEvent("failed", level: .error)
    struct Failed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed: \(error.description)"
        }
    }
}

struct LogErrorTestFailure: LocalizedError {
    var errorDescription: String? {
        "Unavailable"
    }

    var failureReason: String? {
        "Offline"
    }

    var recoverySuggestion: String? {
        "Reconnect"
    }
}

struct CodableLogErrorTestFailure: Error, Codable {
    let attempt: Int
    let retryable: Bool
}

struct UnencodableLogErrorTestFailure: Error, Encodable {
    struct EncodingFailure: Error, Equatable {}
    func encode(to _: any Encoder) throws {
        throw EncodingFailure()
    }
}

enum LogErrorTestKey: String, CodingKey {
    case items, name
}

/// Immutable NSError subclass exposes a cycle without retaining itself in stored state.
final class CyclicLogErrorTestFailure: NSError, @unchecked Sendable {
    init() {
        super.init(domain: "Cycle", code: 1, userInfo: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Not used")
    }

    override var userInfo: [String: Any] {
        [NSUnderlyingErrorKey: self]
    }

    override var localizedDescription: String {
        "Cycle"
    }
}
