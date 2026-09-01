import Foundation

/// A validated dwell duration for one configured projection experience.
public struct ProjectionDwellDuration: Hashable, Sendable {
    public static let allowedSeconds = 30 ... 1800
    public static let defaultValue = try! ProjectionDwellDuration(seconds: 120)

    public let seconds: Int

    public init(seconds: Int) throws {
        guard Self.allowedSeconds.contains(seconds), seconds.isMultiple(of: 30) else {
            throw ProjectionPlaylistError.invalidDwellDuration
        }
        self.seconds = seconds
    }
}

public struct ProjectionPlaylistEntry: Hashable, Sendable {
    public let runnableExperienceID: RunnableProjectionExperienceID
    public let dwellDuration: ProjectionDwellDuration

    public init(
        runnableExperienceID: RunnableProjectionExperienceID,
        dwellDuration: ProjectionDwellDuration,
    ) {
        self.runnableExperienceID = runnableExperienceID
        self.dwellDuration = dwellDuration
    }

    public var experienceID: ProjectionExperienceID {
        runnableExperienceID.experienceID
    }
}

public enum ProjectionPlaylistError: Error, Equatable, Sendable {
    case duplicateExperience
    case unknownExperience
    case unavailableExperience
    case unconfiguredExperience
    case invalidSelection
    case invalidDwellDuration
}

/// The persisted order and rotation policy for configured projection experiences.
public struct ProjectionPlaylist: Equatable, Sendable {
    public let entries: [ProjectionPlaylistEntry]
    public let automaticRotationEnabled: Bool
    public let selectedRunnableExperienceID: RunnableProjectionExperienceID?

    public init(
        entries: [ProjectionPlaylistEntry],
        automaticRotationEnabled: Bool,
        selectedExperienceID: RunnableProjectionExperienceID?,
        configuredExperienceIDs: Set<RunnableProjectionExperienceID>,
        catalog: ProjectionExperienceCatalog,
    ) throws {
        let entryIDs = entries.map(\.runnableExperienceID)
        guard Set(entryIDs).count == entryIDs.count else {
            throw ProjectionPlaylistError.duplicateExperience
        }
        for id in entryIDs {
            guard let descriptor = catalog[id.experienceID] else {
                throw ProjectionPlaylistError.unknownExperience
            }
            guard descriptor.availability.runnableExperienceID == id else {
                throw ProjectionPlaylistError.unavailableExperience
            }
            guard configuredExperienceIDs.contains(id) else {
                throw ProjectionPlaylistError.unconfiguredExperience
            }
        }
        if let selectedExperienceID {
            guard entryIDs.contains(selectedExperienceID) else {
                throw ProjectionPlaylistError.invalidSelection
            }
        } else if entries.isEmpty == false {
            throw ProjectionPlaylistError.invalidSelection
        }
        self.entries = entries
        self.automaticRotationEnabled = automaticRotationEnabled
        selectedRunnableExperienceID = selectedExperienceID
    }

    public var selectedExperienceID: ProjectionExperienceID? {
        selectedRunnableExperienceID?.experienceID
    }

    public var rotatesAutomatically: Bool {
        automaticRotationEnabled && entries.count > 1
    }

    public func entry(
        for id: RunnableProjectionExperienceID,
    ) -> ProjectionPlaylistEntry? {
        entries.first { $0.runnableExperienceID == id }
    }

    public func runnableExperienceID(
        for experienceID: ProjectionExperienceID,
    ) -> RunnableProjectionExperienceID? {
        entries.first { $0.experienceID == experienceID }?.runnableExperienceID
    }

    public func experience(
        after id: RunnableProjectionExperienceID,
    ) -> RunnableProjectionExperienceID? {
        adjacentExperience(to: id, offset: 1)
    }

    public func experience(
        before id: RunnableProjectionExperienceID,
    ) -> RunnableProjectionExperienceID? {
        adjacentExperience(to: id, offset: -1)
    }

    public func addingConfiguredExperience(
        _ id: RunnableProjectionExperienceID,
        dwellDuration: ProjectionDwellDuration,
        configuredExperienceIDs: Set<RunnableProjectionExperienceID>,
        catalog: ProjectionExperienceCatalog,
    ) throws -> ProjectionPlaylist {
        guard entry(for: id) == nil else {
            throw ProjectionPlaylistError.duplicateExperience
        }
        let newEntries = entries + [
            ProjectionPlaylistEntry(runnableExperienceID: id, dwellDuration: dwellDuration),
        ]
        return try ProjectionPlaylist(
            entries: newEntries,
            automaticRotationEnabled: newEntries.count > 1 || automaticRotationEnabled,
            selectedExperienceID: selectedRunnableExperienceID ?? id,
            configuredExperienceIDs: configuredExperienceIDs,
            catalog: catalog,
        )
    }

    private func adjacentExperience(
        to id: RunnableProjectionExperienceID,
        offset: Int,
    ) -> RunnableProjectionExperienceID? {
        guard entries.count > 1,
              let currentIndex = entries.firstIndex(where: { $0.runnableExperienceID == id })
        else {
            return nil
        }
        let index = (currentIndex + offset + entries.count) % entries.count
        return entries[index].runnableExperienceID
    }
}
