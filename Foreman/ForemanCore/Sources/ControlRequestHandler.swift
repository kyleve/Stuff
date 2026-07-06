import Foundation

/// Maps a decoded ``ControlRequest`` to the matching ``ForemanServices``
/// intent and wraps the outcome in a ``ControlResponse``.
///
/// Transport-agnostic on purpose: the app target's socket server does the raw
/// I/O and hands decoded requests here, so this — and the services intents it
/// calls — is what `ForemanCoreTests` covers. Every thrown error becomes a
/// `.failure` response (the reason is localized), never a crash or a silent
/// success.
@MainActor
public struct ControlRequestHandler {
    private let services: ForemanServices

    public init(services: ForemanServices) {
        self.services = services
    }

    public func handle(_ request: ControlRequest) async -> ControlResponse {
        do {
            switch request {
                case .describe:
                    return .describe(services.describe())
                case let .adopt(path, provenanceDTO):
                    let provenance = try provenanceDTO.model()
                    let status = try services.adoptAndStartWorker(
                        at: URL(fileURLWithPath: path),
                        provenance: provenance,
                    )
                    return .repo(status)
                case let .removeCopy(path):
                    try await services.removeCopy(at: URL(fileURLWithPath: path))
                    return .removed(path: path)
            }
        } catch {
            return .failure(message: error.localizedDescription)
        }
    }
}
