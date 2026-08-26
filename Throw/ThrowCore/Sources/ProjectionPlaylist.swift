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
    public let experienceID: ProjectionExperienceID
    public let dwellDuration: ProjectionDwellDuration

    public init(
        experienceID: ProjectionExperienceID,
        dwellDuration: ProjectionDwellDuration,
    ) {
        self.experienceID = experienceID
        self.dwellDuration = dwellDuration
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
    public let selectedExperienceID: ProjectionExperienceID?

    public init(
        entries: [ProjectionPlaylistEntry],
        automaticRotationEnabled: Bool,
        selectedExperienceID: ProjectionExperienceID?,
        configuredExperienceIDs: Set<ProjectionExperienceID>,
        catalog: ProjectionExperienceCatalog,
    ) throws {
        let entryIDs = entries.map(\.experienceID)
        guard Set(entryIDs).count == entryIDs.count else {
            throw ProjectionPlaylistError.duplicateExperience
        }
        for id in entryIDs {
            guard let descriptor = catalog[id] else {
                throw ProjectionPlaylistError.unknownExperience
            }
            guard descriptor.availability == .enabled else {
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
        self.selectedExperienceID = selectedExperienceID
    }

    public var rotatesAutomatically: Bool {
        automaticRotationEnabled && entries.count > 1
    }

    public func entry(for id: ProjectionExperienceID) -> ProjectionPlaylistEntry? {
        entries.first { $0.experienceID == id }
    }

    public func experience(after id: ProjectionExperienceID) -> ProjectionExperienceID? {
        adjacentExperience(to: id, offset: 1)
    }

    public func experience(before id: ProjectionExperienceID) -> ProjectionExperienceID? {
        adjacentExperience(to: id, offset: -1)
    }

    public func addingConfiguredExperience(
        _ id: ProjectionExperienceID,
        dwellDuration: ProjectionDwellDuration,
        configuredExperienceIDs: Set<ProjectionExperienceID>,
        catalog: ProjectionExperienceCatalog,
    ) throws -> ProjectionPlaylist {
        guard entry(for: id) == nil else {
            throw ProjectionPlaylistError.duplicateExperience
        }
        let newEntries = entries + [
            ProjectionPlaylistEntry(experienceID: id, dwellDuration: dwellDuration),
        ]
        return try ProjectionPlaylist(
            entries: newEntries,
            automaticRotationEnabled: newEntries.count > 1 || automaticRotationEnabled,
            selectedExperienceID: selectedExperienceID ?? id,
            configuredExperienceIDs: configuredExperienceIDs,
            catalog: catalog,
        )
    }

    private func adjacentExperience(
        to id: ProjectionExperienceID,
        offset: Int,
    ) -> ProjectionExperienceID? {
        guard entries.count > 1,
              let currentIndex = entries.firstIndex(where: { $0.experienceID == id })
        else {
            return nil
        }
        let index = (currentIndex + offset + entries.count) % entries.count
        return entries[index].experienceID
    }
}
