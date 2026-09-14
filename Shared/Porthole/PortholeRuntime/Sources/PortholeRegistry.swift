import Foundation
@_exported import PortholeCore

/// One application-owned registry mediates every debugger call and live object.
public actor PortholeRegistry: PortholeExecuting, PortholeObservationOwning {
    public typealias Handler = @Sendable (PortholeInvocation, PortholeRegistry) async throws
        -> PortholeValue

    private struct Registration {
        let capability: PortholeCapability
        let handler: Handler?
    }

    private struct RunningOperation {
        let invocation: PortholeInvocation
        let task: Task<PortholeValue, Error>
    }

    private let journal: PortholeOperationJournal
    private let objectRegistryID = UUID()
    private var readReceipts = PortholeReadReceiptCache(
        maximumCount: 256,
        maximumBytes: 8 * 1024 * 1024,
    )
    private var enabled = false
    private var activationGeneration = UUID()
    private var scopes: [PortholeScopeID: PortholeScopeToken] = [:]
    private var registrations: [PortholeScopeToken: [PortholeSymbolID: Registration]] = [:]
    private var objects: PortholeObjectStore
    private var observations = PortholeObservationStore()
    private var coverageStore = PortholeCoverageStore(
        maximumModules: 256,
        maximumDeclarations: 100_000,
        maximumBytes: 64 * 1024 * 1024,
    )
    private var approvals: [UUID: PortholeInvocation] = [:]
    private var pending: [UUID: PortholeActionProposal] = [:]
    private var running: [UUID: RunningOperation] = [:]
    private var activeRequests: [UUID: PortholeInvocation] = [:]
    private var sources: [PortholeScopeToken: [String: PortholeSourceFile]] = [:]
    private var contexts: [PortholeScopeToken: [PortholeContextID: PortholeContext]] = [:]

    public init(journal: PortholeOperationJournal, objectLimit: Int) {
        precondition(objectLimit > 0)
        self.journal = journal
        objects = PortholeObjectStore(capacity: objectLimit)
    }

    @_spi(Testing)
    public init(
        journal: PortholeOperationJournal,
        objectLimit: Int,
        readReceiptLimit: Int,
        readReceiptByteLimit: Int,
    ) {
        precondition(objectLimit > 0)
        self.journal = journal
        objects = PortholeObjectStore(capacity: objectLimit)
        readReceipts = PortholeReadReceiptCache(
            maximumCount: readReceiptLimit,
            maximumBytes: readReceiptByteLimit,
        )
    }

    @_spi(Testing)
    public init(
        journal: PortholeOperationJournal,
        objectLimit: Int,
        coverageModuleLimit: Int,
        coverageDeclarationLimit: Int,
        coverageByteLimit: Int,
    ) {
        precondition(objectLimit > 0)
        self.journal = journal
        objects = PortholeObjectStore(capacity: objectLimit)
        coverageStore = PortholeCoverageStore(
            maximumModules: coverageModuleLimit,
            maximumDeclarations: coverageDeclarationLimit,
            maximumBytes: coverageByteLimit,
        )
    }

    public func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if !value {
            activationGeneration = UUID()
            for leaseID in observations.disable() {
                objects.finish(operationID: leaseID)
            }
            readReceipts.removeAll()
            approvals.removeAll()
            pending.removeAll()
            for operation in running.values {
                operation.task.cancel()
            }
        }
    }

    public func isEnabled() -> Bool {
        enabled
    }

    public func createScope(id: PortholeScopeID) -> PortholeScopeToken {
        if let existing = scopes[id] { invalidate(existing) }
        let token = PortholeScopeToken(id: id, generation: UUID())
        scopes[id] = token
        registrations[token] = [:]
        sources[token] = [:]
        contexts[token] = [:]
        return token
    }

    public func invalidate(_ scope: PortholeScopeToken) {
        guard scopes[scope.id] == scope else { return }
        scopes[scope.id] = nil
        registrations[scope] = nil
        sources[scope] = nil
        coverageStore.invalidate(scope)
        contexts[scope] = nil
        readReceipts.remove(scope: scope)
        for leaseID in observations.invalidate(scope) {
            objects.finish(operationID: leaseID)
        }
        if scopes.isEmpty { observations.clearEndedOwners() }
        objects.invalidate(scope)
        approvals = approvals.filter { $0.value.scope != scope }
        pending = pending.filter { $0.value.invocation.scope != scope }
        for operation in running.values where operation.invocation.scope == scope {
            operation.task.cancel()
        }
    }

    public func describe(_ capability: PortholeCapability, in scope: PortholeScopeToken) throws {
        try checkScope(scope)
        guard registrations[scope]?[capability.id] == nil else {
            throw PortholeError.invalidArguments("Duplicate capability: \(capability.id.rawValue)")
        }
        try coverageStore.validate(capability, hasHandler: false, in: scope)
        registrations[scope]?[capability.id] = Registration(capability: capability, handler: nil)
    }

    public func register(
        _ capability: PortholeCapability,
        in scope: PortholeScopeToken,
        handler: @escaping Handler,
    ) throws {
        try checkScope(scope)
        guard capability.availability == .callable else {
            throw PortholeError.invalidArguments("Only callable capabilities accept handlers")
        }
        guard registrations[scope]?[capability.id] == nil else {
            throw PortholeError.invalidArguments("Duplicate capability: \(capability.id.rawValue)")
        }
        try coverageStore.validate(capability, hasHandler: true, in: scope)
        registrations[scope]?[capability.id] = Registration(
            capability: capability,
            handler: handler,
        )
    }

    public func capabilities(in scope: PortholeScopeToken) throws -> [PortholeCapability] {
        try checkActive(scope)
        return (registrations[scope]?.values.map(\.capability) ?? []).sorted {
            $0.id.rawValue < $1.id.rawValue
        }
    }

    public func installSourceArchive(_ json: String, in scope: PortholeScopeToken) throws {
        try checkScope(scope)
        let files = try JSONDecoder().decode([PortholeSourceFile].self, from: Data(json.utf8))
        guard files.allSatisfy(\.hasValidHash) else {
            throw PortholeError
                .invalidArguments(
                    "The bundled source archive has a content hash mismatch. Rebuild its generated catalog.",
                )
        }
        var merged = sources[scope] ?? [:]
        for file in files {
            if let previous = merged[file.path], previous != file {
                throw PortholeError.invalidArguments("Conflicting source file: \(file.path)")
            }
            merged[file.path] = file
        }
        sources[scope] = merged
    }

    /// Install complete source coverage after this module finishes its compiled registrations.
    public func installCoverage(_ json: String, in scope: PortholeScopeToken) throws {
        try checkScope(scope)
        let installed = registrations[scope] ?? [:]
        try coverageStore.install(json, in: scope, sources: sources[scope] ?? [:]) { symbolID in
            installed[symbolID].map {
                .init(capability: $0.capability, hasHandler: $0.handler != nil)
            }
        }
    }

    public func coverageModules(
        in scope: PortholeScopeToken,
        offset: Int,
        limit: Int,
    ) throws -> PortholeCoverageModulePage {
        try checkActive(scope)
        let installed = registrations[scope] ?? [:]
        return try coverageStore.modules(in: scope, offset: offset, limit: limit) { symbolID in
            installed[symbolID].map {
                .init(capability: $0.capability, hasHandler: $0.handler != nil)
            }
        }
    }

    public func coverage(
        in scope: PortholeScopeToken,
        query: PortholeCoverageQuery,
    ) throws -> PortholeCoveragePage {
        try checkActive(scope)
        let installed = registrations[scope] ?? [:]
        return try coverageStore.declarations(in: scope, query: query) { symbolID in
            installed[symbolID].map {
                .init(capability: $0.capability, hasHandler: $0.handler != nil)
            }
        }
    }

    public func sourceFiles(in scope: PortholeScopeToken) throws -> [PortholeSourceFile] {
        try checkActive(scope)
        return (sources[scope]?.values.map(\.self) ?? []).sorted { $0.path < $1.path }
    }

    public func capture(_ context: PortholeContext) throws {
        try checkActive(context.scope)
        guard context.objects.allSatisfy({ $0.scope == context.scope }) else {
            throw PortholeError.staleScope
        }
        contexts[context.scope]?[context.id] = context
    }

    public func capturedContexts(in scope: PortholeScopeToken) throws -> [PortholeContext] {
        try checkActive(scope)
        return (contexts[scope]?.values.map(\.self) ?? []).sorted { $0.capturedAt > $1.capturedAt }
    }

    public func objectReferences(in scope: PortholeScopeToken) throws -> [PortholeObjectReference] {
        try checkActive(scope)
        return objects.references(in: scope)
    }

    public func pendingApprovals() -> [PortholeActionProposal] {
        pending.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Trusted conversation restoration reads receipts without invoking saved calls.
    public func operationRecord(for operationID: UUID) async throws -> PortholeOperationRecord? {
        let durable = try await journal.record(for: operationID)
        return durable ?? readReceipts.record(for: operationID)
    }

    /// This trusted UI boundary is deliberately absent from PortholeExecuting.
    public func approve(_ proposal: PortholeActionProposal) throws {
        try checkActive(proposal.invocation.scope)
        guard pending[proposal.id] == proposal else { throw PortholeError.operationConflict }
        approvals[proposal.id] = proposal.invocation
        pending[proposal.id] = nil
    }

    public func reject(operationID: UUID) {
        approvals[operationID] = nil
        pending[operationID] = nil
    }

    public func invoke(_ invocation: PortholeInvocation) async throws -> PortholeValue {
        try checkActive(invocation.scope)
        let generation = activationGeneration
        if let active = activeRequests[invocation.id] {
            guard active == invocation else { throw PortholeError.operationConflict }
            throw PortholeError.operationInProgress
        }
        activeRequests[invocation.id] = invocation
        defer { activeRequests[invocation.id] = nil }
        guard let registration = registrations[invocation.scope]?[invocation.capabilityID] else {
            throw PortholeError.unknownCapability(invocation.capabilityID)
        }
        guard let handler = registration.handler else {
            throw PortholeError.unsupported("No compiled binding is available")
        }
        try PortholeSchema.object(registration.capability.parameters).validate(invocation.arguments)
        if let operation = running[invocation.id] {
            guard operation.invocation == invocation else { throw PortholeError.operationConflict }
            throw PortholeError.operationInProgress
        }
        let durableReceipt = try await journal.record(for: invocation.id)
        try checkActive(invocation.scope, generation: generation)
        try authorizeObservationControl(invocation)
        if let previous = durableReceipt ?? readReceipts.record(for: invocation.id) {
            guard previous.invocation == invocation else { throw PortholeError.operationConflict }
            switch previous.status {
                case let .succeeded(value): return value
                case let .failed(message): throw PortholeError.operationFailed(message)
                case .started, .uncertain: throw PortholeError.uncertainOperation
            }
        }
        // Another request can enter while the journal actor answers.
        guard running[invocation.id] == nil else { throw PortholeError.operationInProgress }
        if registration.capability.effect.requiresApproval {
            guard approvals[invocation.id] == invocation else {
                let proposal = PortholeActionProposal(
                    invocation: invocation,
                    capability: registration.capability,
                )
                if let existing = pending[invocation.id], existing != proposal {
                    throw PortholeError.operationConflict
                }
                pending[invocation.id] = proposal
                throw PortholeError.approvalRequired(proposal)
            }
            approvals[invocation.id] = nil
        }
        try objects.lease(
            PortholeObjectReferences.inArguments(of: invocation),
            operationID: invocation.id,
        )
        defer { objects.finish(operationID: invocation.id) }
        let operation = PortholeObjectOperation(
            registryID: objectRegistryID,
            operationID: invocation.id,
        )
        let requiresDurableReceipt = registration.capability.effect != .read
        let task = Task { [journal] in
            try await PortholeObjectOperation.$current.withValue(operation) {
                if requiresDurableReceipt {
                    try await journal.write(PortholeOperationRecord(
                        invocation: invocation,
                        status: .started,
                    ))
                }
                try Task.checkCancellation()
                return try await handler(invocation, self)
            }
        }
        running[invocation.id] = RunningOperation(invocation: invocation, task: task)
        defer { running[invocation.id] = nil }
        return try await withTaskCancellationHandler {
            let result: PortholeValue
            do {
                result = try await task.value
                try registration.capability.result.validate(result)
            } catch {
                let status: PortholeOperationStatus = registration.capability.effect
                    .requiresApproval
                    ? .uncertain : .failed(error.localizedDescription)
                let receipt = PortholeOperationRecord(invocation: invocation, status: status)
                if requiresDurableReceipt { try await journal.write(receipt) }
                else if enabled, !task.isCancelled,
                        scopes[invocation.scope.id] == invocation.scope
                {
                    try readReceipts.insert(receipt)
                }
                throw error
            }
            // Completion and delivery are separate: a replaced scope must not
            // receive this value, but a completed mutation stays completed.
            let receipt = PortholeOperationRecord(
                invocation: invocation,
                status: .succeeded(result),
            )
            if requiresDurableReceipt { try await journal.write(receipt) }
            else if enabled, !task.isCancelled, scopes[invocation.scope.id] == invocation.scope {
                try readReceipts.insert(receipt)
            }
            try checkActive(invocation.scope, generation: generation)
            guard !task.isCancelled else { throw CancellationError() }
            try Task.checkCancellation()
            return result
        } onCancel: { task.cancel() }
    }

    func beginObservation(
        _ request: PortholeObservationRequest,
        in scope: PortholeScopeToken,
    ) throws -> PortholeObservationReference {
        try checkActive(scope)
        try Task.checkCancellation()
        guard request.invocation.scope == scope else { throw PortholeError.staleScope }
        guard let registration = registrations[scope]?[request.invocation.capabilityID] else {
            throw PortholeError.unknownCapability(request.invocation.capabilityID)
        }
        guard registration.capability.availability == .callable,
              registration.capability.effect == .read, registration.handler != nil
        else {
            throw PortholeError
                .invalidArguments(
                    "Observations require a callable capability classified as read-only.",
                )
        }
        try PortholeSchema.object(registration.capability.parameters)
            .validate(request.invocation.arguments)
        let owner = PortholeObservationOwnership.current
        guard try observations.validateStart(request, owner: owner)
        else { return request.reference }
        let leaseID = UUID()
        try objects.lease(
            PortholeObjectReferences.inArguments(of: request.invocation),
            operationID: leaseID,
        )
        let generation = activationGeneration
        observations.start(
            request,
            generation: generation,
            owner: owner,
            leaseID: leaseID,
            execute: { [weak self] invocation in
                guard let self else { throw CancellationError() }
                return try await executeObservation(invocation, generation: generation)
            },
            report: { [weak self] result in
                guard let self else { return false }
                return await publishObservation(
                    result,
                    reference: request.reference,
                    generation: generation,
                )
            },
        )
        return request.reference
    }

    private func authorizeObservationControl(_ invocation: PortholeInvocation) throws {
        let reference: PortholeObservationReference
        switch invocation.capabilityID {
            case PortholeObservationCapabilities.start:
                guard let request = invocation.arguments["request"]
                else { throw PortholeError.invalidArguments("request is required") }
                reference = try request.decode(PortholeObservationRequest.self).reference
            case PortholeObservationCapabilities.read, PortholeObservationCapabilities.stop:
                guard let value = invocation.arguments["observation"]
                else { throw PortholeError.invalidArguments("observation is required") }
                reference = try value.decode(PortholeObservationReference.self)
            default: return
        }
        guard reference.scope == invocation.scope else { throw PortholeError.staleScope }
        try observations.authorize(reference, owner: PortholeObservationOwnership.current)
    }

    private func executeObservation(
        _ invocation: PortholeInvocation,
        generation: UUID,
    ) async throws -> PortholeValue {
        try checkActive(invocation.scope, generation: generation)
        try Task.checkCancellation()
        let value = try await invoke(invocation)
        try checkActive(invocation.scope, generation: generation)
        try Task.checkCancellation()
        return value
    }

    private func publishObservation(
        _ result: Result<PortholeObservationStore.CapturedValue, any Error>,
        reference: PortholeObservationReference,
        generation: UUID,
    ) -> Bool {
        let update = observations.publish(result, for: reference, generation: generation)
        if let leaseID = update.releasedLeaseID { objects.finish(operationID: leaseID) }
        return update.shouldContinue
    }

    func observationSnapshot(
        _ reference: PortholeObservationReference,
        in scope: PortholeScopeToken,
        waiterID: UUID,
        afterSequence: Int64?,
        waitMilliseconds: Int,
    ) async throws -> PortholeObservationSnapshot {
        try checkActive(scope)
        guard reference.scope == scope else { throw PortholeError.staleScope }
        try observations.authorize(reference, owner: PortholeObservationOwnership.current)
        let generation = activationGeneration
        if let snapshot = try observations.snapshotIfReady(
            reference,
            afterSequence: afterSequence,
            waitMilliseconds: waitMilliseconds,
        ) {
            return snapshot
        }
        let snapshot = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                do {
                    try checkActive(scope, generation: generation)
                    try observations.wait(
                        for: reference,
                        waiterID: waiterID,
                        afterSequence: afterSequence,
                        waitMilliseconds: waitMilliseconds,
                        continuation: continuation,
                        expired: { [weak self] error in
                            await self?.finishObservationRead(waiterID: waiterID, error: error)
                        },
                    )
                } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            Task { await self.finishObservationRead(waiterID: waiterID, error: CancellationError())
            }
        }
        try checkActive(scope, generation: generation)
        try Task.checkCancellation()
        return snapshot
    }

    private func finishObservationRead(waiterID: UUID, error: (any Error)?) {
        observations.finishRead(waiterID: waiterID, error: error)
    }

    func endObservation(
        _ reference: PortholeObservationReference,
        in scope: PortholeScopeToken,
    ) throws {
        try checkActive(scope)
        guard reference.scope == scope else { throw PortholeError.staleScope }
        if let leaseID = try observations.stop(
            reference,
            owner: PortholeObservationOwnership.current,
        ) { objects.finish(operationID: leaseID) }
    }

    public func stopObservations(ownedBy owner: PortholeObservationOwnerID) {
        for leaseID in observations.stop(ownedBy: owner) {
            objects.finish(operationID: leaseID)
        }
    }

    /// Explicit application roots survive result-pool eviction until released or invalidated.
    public func retain(
        _ value: some Sendable,
        in scope: PortholeScopeToken,
    ) throws -> PortholeObjectReference {
        try retain(value, in: scope, retention: .scope)
    }

    public func retain<Value: Sendable>(
        _ value: Value,
        in scope: PortholeScopeToken,
        retention: PortholeObjectRetention,
    ) throws -> PortholeObjectReference {
        try retain(value, typeName: String(reflecting: Value.self), in: scope, retention: retention)
    }

    private func retain(
        _ value: some Sendable,
        typeName: String,
        in scope: PortholeScopeToken,
        retention: PortholeObjectRetention,
    ) throws -> PortholeObjectReference {
        try checkScope(scope)
        return try objects.retain(
            value,
            typeName: typeName,
            scope: scope,
            retention: retention,
            operationID: objectOperationID,
        )
    }

    private var objectOperationID: UUID? {
        guard let operation = PortholeObjectOperation.current,
              operation.registryID == objectRegistryID,
              activeRequests[operation.operationID] != nil else { return nil }
        return operation.operationID
    }

    public func encodeMainActor<Value>(
        _ box: PortholeMainActorValue<Value>,
        in scope: PortholeScopeToken,
    ) throws -> PortholeValue {
        try checkActive(scope)
        let reference = try retain(
            box,
            typeName: String(reflecting: Value.self),
            in: scope,
            retention: .results,
        )
        return try .object(["$reference": .encoding(reference)])
    }

    public func resolveMainActor<Value>(
        _ reference: PortholeObjectReference?,
        as type: PortholeMainActorValue<Value>.Type,
        in scope: PortholeScopeToken,
    ) throws -> PortholeMainActorValue<Value> {
        try resolve(reference, as: type, in: scope)
    }

    public func decodeMainActor<Value>(
        _ value: PortholeValue,
        as type: PortholeMainActorValue<Value>.Type,
        in scope: PortholeScopeToken,
    ) throws -> PortholeMainActorValue<Value> {
        try checkActive(scope)
        guard let encodedReference = value["$reference"] else {
            throw PortholeError
                .invalidArguments(
                    "\(String(reflecting: Value.self)) requires a typed MainActor object reference",
                )
        }
        return try resolveMainActor(
            encodedReference.decode(PortholeObjectReference.self),
            as: type,
            in: scope,
        )
    }

    public func resolve<Value: Sendable>(
        _ reference: PortholeObjectReference?,
        as type: Value.Type,
        in scope: PortholeScopeToken,
    ) throws -> Value {
        try checkActive(scope)
        guard let reference, reference.scope == scope else { throw PortholeError.unknownObject }
        let entry = try objects.entry(for: reference, operationID: objectOperationID)
        guard let value = entry.value as? Value else {
            throw PortholeError.wrongObjectType(String(reflecting: type))
        }
        return value
    }

    public func decode<Value: Sendable>(
        _ value: PortholeValue,
        as type: Value.Type,
        in scope: PortholeScopeToken,
    ) throws -> Value {
        try checkActive(scope)
        if let encodedReference = value["$reference"] {
            return try resolve(
                encodedReference.decode(PortholeObjectReference.self),
                as: type,
                in: scope,
            )
        }
        if type == PortholeValue.self, let result = value as? Value { return result }
        guard let decodableType = type as? any Decodable.Type else {
            throw PortholeError
                .invalidArguments("\(String(reflecting: type)) requires a typed object reference")
        }
        let decoded = try JSONDecoder().decode(decodableType, from: value.data())
        guard let result = decoded as? Value else {
            throw PortholeError.wrongObjectType(String(reflecting: type))
        }
        return result
    }

    public func encode(
        _ value: some Sendable,
        in scope: PortholeScopeToken,
    ) throws -> PortholeValue {
        try encode(value, in: scope, retention: .results)
    }

    public func encode<Value: Sendable>(
        _ value: Value,
        in scope: PortholeScopeToken,
        retention: PortholeObjectRetention,
    ) throws -> PortholeValue {
        try checkActive(scope)
        if let value = value as? PortholeValue { return value }
        if Value.self == Void.self { return .null }
        if let encodable = value as? any Encodable {
            return try .encoding(encodable)
        }
        return try .object(["$reference": .encoding(retain(
            value,
            in: scope,
            retention: retention,
        ))])
    }

    /// Reuse a stable field from an immutable captured parent. A parent key must never change
    /// meaning.
    public func encodeChild<Value: Sendable>(
        _ value: Value,
        key: PortholeObjectChildKey,
        of parent: PortholeObjectReference,
        in scope: PortholeScopeToken,
    ) throws -> PortholeValue {
        try checkActive(scope)
        guard parent.scope == scope else { throw PortholeError.staleScope }
        let reference = try objects.retainChild(
            value,
            typeName: String(reflecting: Value.self),
            parent: parent,
            key: key,
            operationID: objectOperationID,
        )
        return try .object(["$reference": .encoding(reference)])
    }

    /// Release only the debugger's reference and its children; native application state is
    /// unchanged.
    public func release(_ reference: PortholeObjectReference) throws {
        try checkActive(reference.scope)
        try objects.release(reference)
    }

    private func checkScope(_ scope: PortholeScopeToken) throws {
        guard scopes[scope.id] == scope else { throw PortholeError.staleScope }
    }

    private func checkActive(_ scope: PortholeScopeToken) throws {
        guard enabled else { throw PortholeError.disabled }
        try checkScope(scope)
    }

    private func checkActive(_ scope: PortholeScopeToken, generation: UUID) throws {
        try checkActive(scope)
        guard activationGeneration == generation else { throw CancellationError() }
    }
}
