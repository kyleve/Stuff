import SFSafeSymbols
import SnapshotKit
import SwiftUI
import ThrowCore

struct ProjectionViewsSettingsView: View {
    @Bindable var session: ThrowSession

    var body: some View {
        let failures = session.postLaunchFailures(for: .playlist)
        List {
            if failures.isEmpty == false {
                Section {
                    SettingsFailureMessages(failures: failures)
                }
            }
            Section {
                Toggle(
                    String(localized: .viewsAutomaticRotation),
                    isOn: Binding(
                        get: { session.projectionPlaylist.automaticRotationEnabled },
                        set: session.setAutomaticExperienceRotationEnabled,
                    ),
                )
                .disabled(session.projectionPlaylist.entries.count < 2)
            } footer: {
                Text(session.projectionPlaylist.entries.count < 2
                    ? .viewsAutomaticRotationDormant
                    : .viewsAutomaticRotationDescription)
            }

            Section(String(localized: .viewsConfigured)) {
                ForEach(session.projectionPlaylist.entries, id: \.experienceID) { entry in
                    configuredRow(entry)
                }
                .onMove(perform: session.moveExperience)
            }

            if session.projectionPlaylist.entry(for: .transit) == nil {
                Section(String(localized: .viewsAvailable)) {
                    plannedTransitRow
                }
            }
        }
        .navigationTitle(Text(.viewsTitle))
        .toolbar {
            if session.projectionPlaylist.entries.count > 1 {
                EditButton()
            }
        }
    }

    @ViewBuilder private func configuredRow(_ entry: ProjectionPlaylistEntry) -> some View {
        let presentation = ProjectionExperiencePresentation(id: entry.experienceID)
        VStack(alignment: .leading, spacing: 8) {
            if entry.experienceID == .airAndSpace {
                NavigationLink(value: ThrowSettingsDestination.airAndSpace) {
                    experienceLabel(
                        presentation: presentation,
                        detail: String(localized: .viewsConfiguredStatus),
                    )
                }
            } else {
                experienceLabel(
                    presentation: presentation,
                    detail: String(localized: .viewsConfiguredStatus),
                )
            }
            FeedHealthRow(health: session.health(for: entry.experienceID))
            Stepper(
                value: Binding(
                    get: {
                        session.projectionPlaylist.entry(for: entry.experienceID)?
                            .dwellDuration.seconds ?? entry.dwellDuration.seconds
                    },
                    set: { seconds in
                        session.setExperienceDwellDuration(
                            seconds: seconds,
                            for: entry.experienceID,
                        )
                    },
                ),
                in: ProjectionDwellDuration.allowedSeconds,
                step: 30,
            ) {
                LabeledContent(String(localized: .viewsDwell)) {
                    Text(
                        Duration.seconds(entry.dwellDuration.seconds),
                        format: .time(pattern: .minuteSecond),
                    )
                }
            }
        }
    }

    private var plannedTransitRow: some View {
        let presentation = ProjectionExperiencePresentation(id: .transit)
        return experienceLabel(
            presentation: presentation,
            detail: String(localized: .viewsTransitPlanned),
        )
        .foregroundStyle(.secondary)
        .accessibilityHint(Text(.viewsTransitPlanned))
    }

    private func experienceLabel(
        presentation: ProjectionExperiencePresentation,
        detail: String,
    ) -> some View {
        Label {
            VStack(alignment: .leading) {
                Text(presentation.name)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemSymbol: presentation.symbol)
        }
    }
}

#if DEBUG
    extension ProjectionViewsSettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Air and Space With Planned Transit",
                configurations: [SnapshotConfiguration(device: .iPhoneFullContent)],
                settle: .immediate,
            ) {
                NavigationStack {
                    ProjectionViewsSettingsView(session: .healthyDashboardSnapshotFixture())
                }
                .throwBroadwayRoot()
            }
            SnapshotCase(
                name: "Automatic Rotation Enabled",
                configurations: [SnapshotConfiguration(device: .iPhoneFullContent)],
                settle: .immediate,
            ) {
                NavigationStack {
                    ProjectionViewsSettingsView(
                        session: .experienceDashboardSnapshotFixture(.rotating),
                    )
                }
                .throwBroadwayRoot()
            }
        }
    }

    #Preview {
        ProjectionViewsSettingsView.snapshotPreviews
    }
#endif
