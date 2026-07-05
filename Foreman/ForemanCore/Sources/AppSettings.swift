import Foundation
import Observation

/// The global settings node of the model tree: where to scan for
/// repositories and which `cursor-agent` to run.
///
/// Mutations notify the injected funnel (with which property changed, since
/// the owning tree persists on any change but only rescans for a scan-
/// directory change); reassigning an equal value is a no-op.
@MainActor
@Observable
public final class AppSettings {
    /// Which persisted property changed, for the funnel to react to.
    public enum Change: Sendable {
        case scanDirectory
        case agentExecutable
    }

    /// Directory scanned for git repositories; `nil` means the default
    /// (`~/Development`, see ``resolvedScanDirectory``).
    public var scanDirectory: URL? {
        didSet {
            guard oldValue != scanDirectory else { return }
            onPersistentChange(.scanDirectory)
        }
    }

    /// Explicit `cursor-agent` executable; `nil` means auto-locate via
    /// ``CursorAgentLocator``.
    public var agentExecutable: URL? {
        didSet {
            guard oldValue != agentExecutable else { return }
            onPersistentChange(.agentExecutable)
        }
    }

    /// The scan directory with the `~/Development` default applied.
    public var resolvedScanDirectory: URL {
        scanDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Development")
    }

    private let onPersistentChange: @MainActor (Change) -> Void

    /// Initial values are the saved configuration; assigning them here does
    /// not invoke the funnel.
    public init(
        scanDirectory: URL?,
        agentExecutable: URL?,
        onPersistentChange: @escaping @MainActor (Change) -> Void,
    ) {
        self.scanDirectory = scanDirectory
        self.agentExecutable = agentExecutable
        self.onPersistentChange = onPersistentChange
    }
}
