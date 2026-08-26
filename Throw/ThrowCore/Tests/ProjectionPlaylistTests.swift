import Testing
@testable import ThrowCore

struct ProjectionPlaylistTests {
    private let airEntry = ProjectionPlaylistEntry(
        experienceID: .airAndSpace,
        dwellDuration: .defaultValue,
    )

    @Test(arguments: [30, 120, 1800])
    func acceptsDwellBoundsAndSteps(seconds: Int) throws {
        #expect(try ProjectionDwellDuration(seconds: seconds).seconds == seconds)
    }

    @Test(arguments: [0, 29, 31, 1801])
    func rejectsInvalidDwellDurations(seconds: Int) {
        #expect(throws: ProjectionPlaylistError.invalidDwellDuration) {
            try ProjectionDwellDuration(seconds: seconds)
        }
    }

    @Test func oneConfiguredExperienceLeavesRotationDormant() throws {
        let playlist = try ProjectionPlaylist(
            entries: [airEntry],
            automaticRotationEnabled: true,
            selectedExperienceID: .airAndSpace,
            configuredExperienceIDs: [.airAndSpace],
            catalog: .standard,
        )

        #expect(playlist.rotatesAutomatically == false)
        #expect(playlist.experience(after: .airAndSpace) == nil)
    }

    @Test func duplicateEntriesAreRejected() {
        #expect(throws: ProjectionPlaylistError.duplicateExperience) {
            try ProjectionPlaylist(
                entries: [airEntry, airEntry],
                automaticRotationEnabled: true,
                selectedExperienceID: .airAndSpace,
                configuredExperienceIDs: [.airAndSpace],
                catalog: .standard,
            )
        }
    }

    @Test func plannedEntriesAreRejected() {
        let transit = ProjectionPlaylistEntry(
            experienceID: .transit,
            dwellDuration: .defaultValue,
        )
        #expect(throws: ProjectionPlaylistError.unavailableExperience) {
            try ProjectionPlaylist(
                entries: [transit],
                automaticRotationEnabled: false,
                selectedExperienceID: .transit,
                configuredExperienceIDs: [.transit],
                catalog: .standard,
            )
        }
    }

    @Test func enabledButUnconfiguredEntryIsRejected() throws {
        let customID = ProjectionExperienceID(rawValue: "custom")
        let customCatalog = ProjectionExperienceCatalog(
            descriptors: [
                ProjectionExperienceDescriptor(
                    id: customID,
                    availability: .enabled,
                    supportedModes: [.map],
                    layerIDs: [.geography],
                    visibleContentKind: .objects,
                    zOrder: 0,
                ),
            ],
            layerCatalog: .standard,
        )
        let entry = ProjectionPlaylistEntry(
            experienceID: customID,
            dwellDuration: .defaultValue,
        )

        #expect(throws: ProjectionPlaylistError.unconfiguredExperience) {
            try ProjectionPlaylist(
                entries: [entry],
                automaticRotationEnabled: false,
                selectedExperienceID: customID,
                configuredExperienceIDs: [],
                catalog: customCatalog,
            )
        }
    }

    @Test func configuringSecondExperienceAppendsDefaultDwellAndEnablesRotation() throws {
        let catalog = enabledTwoExperienceCatalog()
        let first = try ProjectionPlaylist(
            entries: [ProjectionPlaylistEntry(
                experienceID: .airAndSpace,
                dwellDuration: .defaultValue,
            )],
            automaticRotationEnabled: false,
            selectedExperienceID: .airAndSpace,
            configuredExperienceIDs: [.airAndSpace],
            catalog: catalog,
        )

        let playlist = try first.addingConfiguredExperience(
            .transit,
            dwellDuration: .defaultValue,
            configuredExperienceIDs: [.airAndSpace, .transit],
            catalog: catalog,
        )

        #expect(playlist.entries.map(\.experienceID) == [.airAndSpace, .transit])
        #expect(playlist.entry(for: .transit)?.dwellDuration == .defaultValue)
        #expect(playlist.automaticRotationEnabled)
        #expect(playlist.rotatesAutomatically)
    }

    @Test func unknownEntryAndInvalidSelectionAreRejected() {
        let unknown = ProjectionPlaylistEntry(
            experienceID: ProjectionExperienceID(rawValue: "unknown"),
            dwellDuration: .defaultValue,
        )
        #expect(throws: ProjectionPlaylistError.unknownExperience) {
            try ProjectionPlaylist(
                entries: [unknown],
                automaticRotationEnabled: false,
                selectedExperienceID: unknown.experienceID,
                configuredExperienceIDs: [unknown.experienceID],
                catalog: .standard,
            )
        }
        #expect(throws: ProjectionPlaylistError.invalidSelection) {
            try ProjectionPlaylist(
                entries: [airEntry],
                automaticRotationEnabled: false,
                selectedExperienceID: nil,
                configuredExperienceIDs: [.airAndSpace],
                catalog: .standard,
            )
        }
    }

    private func enabledTwoExperienceCatalog() -> ProjectionExperienceCatalog {
        ProjectionExperienceCatalog(
            descriptors: [
                ProjectionExperienceDescriptor(
                    id: .airAndSpace,
                    availability: .enabled,
                    supportedModes: [.map, .trueSky],
                    layerIDs: [.geography, .flights],
                    visibleContentKind: .aircraft,
                    zOrder: 0,
                ),
                ProjectionExperienceDescriptor(
                    id: .transit,
                    availability: .enabled,
                    supportedModes: [.map],
                    layerIDs: [.geography, .transitNetwork, .transitVehicles],
                    visibleContentKind: .vehicles,
                    zOrder: 10,
                ),
            ],
            layerCatalog: .standard,
        )
    }
}
