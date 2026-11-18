@_spi(FlaggerUI) import Flagger
import Observation

/// Observable UI projection and environment entry point for a scoped Flagger.
@MainActor
@Observable
@dynamicMemberLookup
public final class FlaggerModel {
    public private(set) var flags: [FlagSnapshot]
    public private(set) var latestFailure: FlaggerFailure?
    public private(set) var error: (any Error)?
    public var searchText = ""

    public var filteredFlags: [FlagSnapshot] {
        guard searchText.isEmpty == false else { return flags }
        return flags.filter {
            $0.name.localizedStandardContains(searchText)
                || $0.id.rawValue.localizedStandardContains(searchText)
                || $0.group.name.localizedStandardContains(searchText)
                || $0.source.name.localizedStandardContains(searchText)
                || ($0.detail?.localizedStandardContains(searchText) ?? false)
        }
    }

    var filteredSources: [FlagSourceSection] {
        let sourceBuckets = Dictionary(grouping: filteredFlags, by: \.source)
        return sourceBuckets.map { source, sourceFlags in
            let groupBuckets = Dictionary(grouping: sourceFlags, by: \.group)
            let groups = groupBuckets.map { group, groupFlags in
                FlagGroupSection(id: group.id, name: group.name, flags: groupFlags)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return FlagSourceSection(id: source.id, name: source.name, groups: groups)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private let flagger: Flagger
    @ObservationIgnored private var observationTasks: [Task<Void, Never>] = []

    public init(_ flagger: Flagger) {
        let changes = flagger.changes()
        let failures = flagger.failures()
        self.flagger = flagger
        flags = flagger.snapshots()
        observationTasks = [
            Task { [weak self, flagger] in
                for await _ in changes {
                    guard let self else { return }
                    self.refresh()
                }
            },
            Task { [weak self, flagger] in
                for await failure in failures {
                    guard let self else { return }
                    self.latestFailure = failure
                }
            },
        ]
    }

    deinit {
        for task in observationTasks {
            task.cancel()
        }
    }

    public subscript<Group: FeatureFlagGroup>(
        dynamicMember keyPath: KeyPath<FeatureFlagGroups, Group>,
    ) -> FlagGroupAccessor<Group> {
        let group = FeatureFlagGroups()[keyPath: keyPath]
        return FlagGroupAccessor(group: group, model: self)
    }

    public func dismissError() {
        error = nil
    }

    func value<Value: Codable & Sendable>(
        for flag: Flag<Value, some FeatureFlagBehavior>,
    ) -> Value {
        _ = flags
        return flagger.valueOrDefault(for: flag)
    }

    func throwingValue<Value: Codable & Sendable>(
        for flag: Flag<Value, some FeatureFlagBehavior>,
    ) throws -> Value {
        _ = flags
        return try flagger.value(for: flag)
    }

    func set<Value: Codable & Sendable>(
        _ value: Value,
        for flag: Flag<Value, LiveUpdating>,
    ) async throws {
        do {
            try await flagger.set(value, for: flag)
            refresh()
            error = nil
        } catch {
            self.error = error
            throw error
        }
    }

    func reset(_ flag: Flag<some Codable & Sendable, LiveUpdating>) async throws {
        do {
            try await flagger.reset(flag)
            refresh()
            error = nil
        } catch {
            self.error = error
            throw error
        }
    }

    func setOverride(_ value: JSONValue, for id: FlagID) async {
        await perform { try await flagger.setOverride(value, for: id) }
    }

    func resetOverride(for id: FlagID) async {
        await perform { try await flagger.resetOverride(for: id) }
    }

    private func perform(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            refresh()
            error = nil
        } catch {
            self.error = error
        }
    }

    private func refresh() {
        flags = flagger.snapshots()
    }
}
