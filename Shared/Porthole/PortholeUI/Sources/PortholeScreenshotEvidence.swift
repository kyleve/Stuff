import Foundation
import PortholeCore

/// Native screenshot sources stay outside the automatically exported application modules.
@MainActor
public protocol PortholeScreenshotCapturing {
    func capturePNG() throws -> Data
}

/// Preserves the application image and prevents debugger credentials from entering tool results.
@MainActor
public final class PortholeScreenshotEvidence {
    private enum Capture {
        case absent
        case frozen(Data)
        case unavailable(String)
    }

    private let source: any PortholeScreenshotCapturing
    private let isDebuggerPresented: @MainActor () -> Bool
    private var capture: Capture = .absent

    public init(
        source: any PortholeScreenshotCapturing,
        isDebuggerPresented: @escaping @MainActor () -> Bool,
    ) {
        self.source = source
        self.isDebuggerPresented = isDebuggerPresented
    }

    public func freeze() throws {
        guard !isDebuggerPresented() else {
            throw PortholeError
                .unsupported("Close Porthole before capturing another application image.")
        }
        do { capture = try .frozen(source.capturePNG()) }
        catch {
            capture = .unavailable(error.localizedDescription)
            throw error
        }
    }

    public func png() throws -> Data {
        switch capture {
            case let .frozen(data): return data
            case let .unavailable(message):
                throw PortholeError.unsupported("The application image was unavailable: \(message)")
            case .absent: break
        }
        guard !isDebuggerPresented() else {
            throw PortholeError
                .unsupported("No application image was captured before Porthole opened.")
        }
        return try source.capturePNG()
    }

    public func reset() {
        capture = .absent
    }
}
