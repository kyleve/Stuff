import PortholeRuntime

/// Metadata reads preserve the recorded ownership scope; they never evaluate object members.
@MainActor
protocol PortholeEvidenceReading {
    func objects(in scope: PortholeScopeToken) async throws -> [PortholeObjectReference]
    func capabilities(in scope: PortholeScopeToken) async throws -> [PortholeCapability]
    func contexts(in scope: PortholeScopeToken) async throws -> [PortholeContext]
    func source(path: String, in scope: PortholeScopeToken) async throws -> PortholeSourceFile
}

struct PortholeRegistryEvidenceReader: PortholeEvidenceReading {
    let registry: PortholeRegistry

    func objects(in scope: PortholeScopeToken) async throws -> [PortholeObjectReference] {
        try await registry.objectReferences(in: scope)
    }

    func capabilities(in scope: PortholeScopeToken) async throws -> [PortholeCapability] {
        try await registry.capabilities(in: scope)
    }

    func contexts(in scope: PortholeScopeToken) async throws -> [PortholeContext] {
        try await registry.capturedContexts(in: scope)
    }

    func source(path: String, in scope: PortholeScopeToken) async throws -> PortholeSourceFile {
        guard let file = try await registry.sourceFiles(in: scope).first(where: { $0.path == path })
        else {
            throw PortholeError
                .invalidArguments("The source archive is unavailable for this scope")
        }
        return file
    }
}

/// The reader and call executor belong to one local presentation or remote connection.
@MainActor
struct PortholeEvidenceNavigation {
    let reader: any PortholeEvidenceReading
    let execute: @MainActor (PortholeInvocation) async throws -> PortholeValue

    init(
        reader: any PortholeEvidenceReading,
        execute: @escaping @MainActor (PortholeInvocation) async throws -> PortholeValue,
    ) {
        self.reader = reader
        self.execute = execute
    }

    init(controller: PortholePresentationController) {
        reader = PortholeRegistryEvidenceReader(registry: controller.registry)
        execute = controller.execute
    }
}
