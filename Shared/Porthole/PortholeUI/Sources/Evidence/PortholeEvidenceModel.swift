import Foundation
import Observation
import PortholeRuntime

/// Resolves live handles through their recorded scope without invoking their getters.
@MainActor @Observable
final class PortholeEvidenceModel {
    struct Object {
        let reference: PortholeObjectReference
        let capabilities: [PortholeCapability]
    }

    struct Context {
        let capture: PortholeContext
    }

    struct Source {
        let file: PortholeSourceFile
        let line: Int
    }

    enum Content { case object(Object), context(Context), source(Source) }
    enum State { case loading, loaded(Content), failed(String) }

    let reference: PortholeEvidenceReference
    private let reader: any PortholeEvidenceReading
    private(set) var state: State = .loading

    init(reference: PortholeEvidenceReference, registry: PortholeRegistry) {
        self.reference = reference
        reader = PortholeRegistryEvidenceReader(registry: registry)
    }

    init(reference: PortholeEvidenceReference, reader: any PortholeEvidenceReading) {
        self.reference = reference
        self.reader = reader
    }

    /// Temporary view rehosting keeps resolved evidence. An explicit retry performs a fresh read.
    func loadIfNeeded() async {
        switch state {
            case .loading: await load()
            case .loaded, .failed: return
        }
    }

    func load() async {
        state = .loading
        do {
            let content: Content
            switch reference {
                case let .object(reference):
                    let objects = try await reader.objects(in: reference.scope)
                    guard objects.contains(reference) else { throw PortholeError.unknownObject }
                    let capabilities = try await reader.capabilities(in: reference.scope)
                        .filter { Self.isCandidate($0, for: reference) }
                    content = .object(Object(reference: reference, capabilities: capabilities))
                case let .context(context): content = .context(Context(capture: context))
                case let .contextLink(link, scope):
                    guard let context = try await reader.contexts(in: scope)
                        .first(where: { $0.id == link.id && $0.scope == scope })
                    else {
                        throw PortholeError
                            .invalidArguments("The referenced context is no longer available")
                    }
                    content = .context(Context(capture: context))
                case let .source(reference):
                    let file = try await reader.source(path: reference.path, in: reference.scope)
                    guard file.sha256 == reference.sha256, file.hasValidHash else {
                        throw PortholeError
                            .invalidArguments(
                                "The installed source does not match this evidence's SHA-256",
                            )
                    }
                    content = .source(Source(file: file, line: reference.line))
                case let .sourceLocation(location, scope):
                    let file = try await reader.source(path: location.path, in: scope)
                    guard file.hasValidHash else {
                        throw PortholeError
                            .invalidArguments("Source content failed its SHA-256 check")
                    }
                    content = .source(Source(file: file, line: location.line))
                case let .savedSource(file):
                    guard file.hasValidHash
                    else {
                        throw PortholeError
                            .invalidArguments("Saved source content failed its SHA-256 check")
                    }
                    content = .source(Source(file: file, line: 1))
            }
            try Task.checkCancellation()
            state = .loaded(content)
        } catch is CancellationError { return }
        catch {
            PortholeUILog.failures
                .error("Evidence lookup failed: \(String(describing: error), privacy: .private)")
            state = .failed(error.localizedDescription)
        }
    }

    private static func isCandidate(
        _ capability: PortholeCapability,
        for object: PortholeObjectReference,
    ) -> Bool {
        let prefix = capability.module.rawValue + "."
        guard object.typeName.hasPrefix(prefix) else { return false }
        let type = String(object.typeName.dropFirst(prefix.count))
        return capability.name.hasPrefix(type + ".")
    }
}
