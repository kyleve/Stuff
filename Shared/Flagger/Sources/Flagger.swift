import Foundation
import os
import SwiftData

/// A scoped feature-flag container with synchronous cached reads and serialized writes.
public actor Flagger {
    public enum Storage: Sendable {
        case inMemory
        case onDisk(name: String)
        case atURL(URL)
        case container(ModelContainer)
    }

    private struct Resolution {
        let value: JSONValue
        let failure: FlaggerFailure?
    }

    private struct State {
        let definitions: [FlagID: FlagDefinition]
        let orderedDefinitions: [FlagDefinition]
        var storedValues: [FlagID: JSONValue]
        var resolutions: [FlagID: Resolution]
        var appliedStoreRevision: UInt64
        var changeObservers: [UUID: AsyncStream<FlagID>.Continuation] = [:]
        var failureObservers: [UUID: AsyncStream<FlaggerFailure>.Continuation] = [:]
    }

    private nonisolated let state: OSAllocatedUnfairLock<State>
    private let persistence: FlaggerPersistence

    private init(
        definitions: [FlagDefinition],
        storedSnapshot: FlaggerPersistence.StoreSnapshot,
        persistence: FlaggerPersistence,
    ) {
        let indexed = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        var resolutions: [FlagID: Resolution] = [:]
        for definition in definitions where definition.behavior == .readOnceOnLaunch {
            resolutions[definition.id] = Self.resolve(
                definition,
                storedSnapshot.values[definition.id],
            )
        }
        state = OSAllocatedUnfairLock(initialState: State(
            definitions: indexed,
            orderedDefinitions: definitions,
            storedValues: storedSnapshot.values,
            resolutions: resolutions,
            appliedStoreRevision: storedSnapshot.revision,
        ))
        self.persistence = persistence
    }

    public static func open(
        sources: FlagSourceRegistry,
        storage: Storage,
    ) async throws -> Flagger {
        let definitions = try definitions(from: sources)
        let container = try await makeContainer(storage: storage)
        let persistence = FlaggerPersistence(modelContainer: container)
        var storedSnapshot = try await persistence.load()
        let redundantOverrideIDs = Set(definitions.compactMap { definition in
            storedSnapshot.values[definition.id] == definition.defaultValue ? definition.id : nil
        })
        if redundantOverrideIDs.isEmpty == false {
            storedSnapshot = try await persistence.remove(redundantOverrideIDs)
        }
        return Flagger(
            definitions: definitions,
            storedSnapshot: storedSnapshot,
            persistence: persistence,
        )
    }

    public nonisolated func value<Value: Codable & Sendable>(
        for flag: Flag<Value, some FeatureFlagBehavior>,
    ) throws -> Value {
        let resolution = try resolution(for: flag.id)
        if let failure = resolution.failure { throw failure }
        return try FlagDefinition.value(Value.self, from: resolution.value)
    }

    public nonisolated func valueOrDefault<Value: Codable & Sendable>(
        for flag: Flag<Value, some FeatureFlagBehavior>,
    ) -> Value {
        do {
            return try value(for: flag)
        } catch {
            let failure = error as? FlaggerFailure
                ?? FlaggerFailure(flagID: flag.id, operation: .read, error: error)
            emit(failure)
            return flag.defaultValue
        }
    }

    public func set<Value: Codable & Sendable>(
        _ value: Value,
        for flag: Flag<Value, LiveUpdating>,
    ) async throws {
        let json = try FlagDefinition.json(value)
        try await persist(json, for: flag.id, operation: .write)
    }

    public func reset(
        _ flag: Flag<some Codable & Sendable, LiveUpdating>,
    ) async throws {
        try await persist(nil, for: flag.id, operation: .reset)
    }

    public nonisolated func values<Value: Codable & Sendable>(
        for flag: Flag<Value, LiveUpdating>,
    ) -> AsyncStream<Value> {
        let changes = changes()
        let (stream, continuation) = AsyncStream.makeStream(
            of: Value.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        continuation.yield(valueOrDefault(for: flag))
        let task = Task { [weak self] in
            for await changedID in changes where changedID == flag.id {
                guard let self else { return }
                continuation.yield(self.valueOrDefault(for: flag))
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public nonisolated func changes() -> AsyncStream<FlagID> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: FlagID.self,
            bufferingPolicy: .bufferingNewest(32),
        )
        state.withLock { $0.changeObservers[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { $0.changeObservers[id] = nil }
        }
        return stream
    }

    public nonisolated func failures() -> AsyncStream<FlaggerFailure> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: FlaggerFailure.self,
            bufferingPolicy: .bufferingNewest(16),
        )
        state.withLock { $0.failureObservers[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { $0.failureObservers[id] = nil }
        }
        return stream
    }

    public nonisolated func snapshots() -> [FlagSnapshot] {
        state.withLock { state in
            state.orderedDefinitions.map { definition in
                let stored = state.storedValues[definition.id]
                let frozenResolution = state.resolutions[definition.id]
                let displayedResolution = frozenResolution ?? Self.resolve(definition, stored)
                return FlagSnapshot(
                    id: definition.id,
                    propertyName: definition.propertyName,
                    name: definition.name,
                    detail: definition.detail,
                    source: definition.source,
                    group: definition.group,
                    behavior: definition.behavior,
                    defaultValue: definition.defaultValue,
                    storedValue: stored,
                    effectiveValue: displayedResolution.value,
                    isFrozen: frozenResolution != nil,
                    failure: displayedResolution.failure,
                )
            }
        }
    }

    @_spi(FlaggerUI)
    public func setOverride(_ value: JSONValue, for id: FlagID) async throws {
        try await persist(value, for: id, operation: .write)
    }

    @_spi(FlaggerUI)
    public func resetOverride(for id: FlagID) async throws {
        _ = try registeredDefinition(for: id)
        try await persist(nil, for: id, operation: .reset)
    }

    private nonisolated func resolution(for id: FlagID) throws -> Resolution {
        let (result, emittedChange) = try state.withLock { state -> (Resolution, Bool) in
            guard let definition = state.definitions[id] else {
                throw FlaggerError.unregisteredFlag(id)
            }
            if let existing = state.resolutions[id] { return (existing, false) }
            let resolved = Self.resolve(definition, state.storedValues[id])
            if definition.behavior == .readOnceOnFirstAccess {
                state.resolutions[id] = resolved
                return (resolved, true)
            }
            return (resolved, false)
        }
        if emittedChange { notifyChange(id) }
        return result
    }

    private func persist(
        _ requestedValue: JSONValue?,
        for id: FlagID,
        operation: FlaggerFailure.Operation,
    ) async throws {
        do {
            let definition = try registeredDefinition(for: id)
            if let requestedValue {
                _ = try definition.decode(requestedValue)
            }
            let value = requestedValue == definition.defaultValue ? nil : requestedValue
            let storeSnapshot = try await persistence.persist(value, for: id)
            let changedIDs = state.withLock { state -> [FlagID] in
                guard storeSnapshot.revision > state.appliedStoreRevision else { return [] }
                let oldValues = state.storedValues
                state.appliedStoreRevision = storeSnapshot.revision
                state.storedValues = storeSnapshot.values

                var changedIDs: [FlagID] = []
                for definition in state.orderedDefinitions
                    where oldValues[definition.id] != storeSnapshot.values[definition.id]
                {
                    changedIDs.append(definition.id)
                    if definition.behavior == .liveUpdating {
                        state.resolutions[definition.id] = nil
                    }
                }
                return changedIDs
            }
            for changedID in changedIDs {
                notifyChange(changedID)
            }
        } catch {
            let failure = FlaggerFailure(flagID: id, operation: operation, error: error)
            emit(failure)
            throw failure
        }
    }

    private nonisolated func registeredDefinition(for id: FlagID) throws -> FlagDefinition {
        try state.withLock { state in
            guard let definition = state.definitions[id] else {
                throw FlaggerError.unregisteredFlag(id)
            }
            return definition
        }
    }

    private nonisolated static func resolve(
        _ definition: FlagDefinition,
        _ storedValue: JSONValue?,
    ) -> Resolution {
        let candidate = storedValue ?? definition.defaultValue
        do {
            _ = try definition.decode(candidate)
            return Resolution(value: candidate, failure: nil)
        } catch {
            return Resolution(
                value: definition.defaultValue,
                failure: FlaggerFailure(flagID: definition.id, operation: .read, error: error),
            )
        }
    }

    private nonisolated func notifyChange(_ id: FlagID) {
        let observers = state.withLock { Array($0.changeObservers.values) }
        for observer in observers {
            observer.yield(id)
        }
    }

    private nonisolated func emit(_ failure: FlaggerFailure) {
        let observers = state.withLock { Array($0.failureObservers.values) }
        for observer in observers {
            observer.yield(failure)
        }
    }

    private nonisolated static func definitions(
        from sources: FlagSourceRegistry,
    ) throws -> [FlagDefinition] {
        var sourceIDs: Set<FlagSourceID> = []
        var groupTypes: Set<ObjectIdentifier> = []
        var groupIDs: Set<String> = []
        var flagIDs: Set<FlagID> = []
        var definitions: [FlagDefinition] = []

        for source in sources.registrations {
            precondition(
                sourceIDs.insert(source.metadata.id).inserted,
                "Flag source IDs must be unique.",
            )
            for registration in source.groups.registrations {
                precondition(
                    groupTypes.insert(registration.typeID).inserted,
                    "A flag group type may be registered only once.",
                )
                let qualifiedGroupID = "\(source.metadata.id.rawValue).\(registration.metadata.id.rawValue)"
                precondition(
                    groupIDs.insert(qualifiedGroupID).inserted,
                    "Flag group IDs must be unique within a source.",
                )
                let group = registration.make()
                for child in Mirror(reflecting: group).children {
                    guard let propertyName = child.label,
                          let flag = child.value as? any AnyFeatureFlag
                    else {
                        continue
                    }
                    let definition = try flag.definition(
                        propertyName: propertyName,
                        source: source.metadata,
                        group: registration.metadata,
                    )
                    precondition(
                        flagIDs.insert(definition.id).inserted,
                        "Flag IDs must be unique within a Flagger.",
                    )
                    definitions.append(definition)
                }
            }
        }
        return definitions.sorted {
            ($0.source.name, $0.group.name, $0.name)
                < ($1.source.name, $1.group.name, $1.name)
        }
    }

    @concurrent
    private static func makeContainer(storage: Storage) async throws -> ModelContainer {
        switch storage {
            case .inMemory:
                let schema = Schema([FlagOverride.self])
                let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [configuration])
            case let .onDisk(name):
                precondition(
                    name.isEmpty == false,
                    "An on-disk Flagger store name must not be empty.",
                )
                let schema = Schema([FlagOverride.self])
                let configuration = ModelConfiguration(name, schema: schema)
                return try ModelContainer(for: schema, configurations: [configuration])
            case let .atURL(url):
                let schema = Schema([FlagOverride.self])
                let configuration = ModelConfiguration(schema: schema, url: url)
                return try ModelContainer(for: schema, configurations: [configuration])
            case let .container(container):
                return container
        }
    }
}

public enum FlaggerError: Error, Equatable {
    case unregisteredFlag(FlagID)
}
