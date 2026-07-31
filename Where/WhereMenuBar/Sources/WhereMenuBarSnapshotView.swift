import SwiftUI
import WhereSurface

struct WhereMenuBarSnapshotView: View {
    @Environment(\.openURL) private var openURL

    let generatedAt: Date
    let snapshot: WhereSurfaceSnapshot
    let refreshFailed: Bool

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline) {
                Text(.menuBarTodayTitle)
                    .font(.headline)
                Spacer()
                // The helper can outlive the host app across midnight. Keep
                // the artifact's logical day visible so stale rows never
                // masquerade as observations for the new day.
                Text(snapshot.day, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if snapshot.todayRegions.isEmpty {
                Text(.menuBarTodayEmpty)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.todayRegions) { region in
                    WhereMenuBarRegionRow(region: region)
                }
            }

            Divider()

            Text(.menuBarYearToDateTitle)
                .font(.headline)
            if snapshot.yearToDate.isEmpty {
                Text(.menuBarYearToDateEmpty)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.yearToDate) { dayCount in
                    WhereMenuBarDayCountRow(dayCount: dayCount)
                }
            }

            Divider()

            HStack {
                Text(.menuBarUpdated)
                Text(generatedAt, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if refreshFailed {
                Label(
                    .menuBarRefreshFailed,
                    systemImage: "exclamationmark.triangle",
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button(
                .menuBarOpenWhere,
                systemImage: "arrow.up.forward.app",
                action: openWhere,
            )
        }
    }

    private func openWhere() {
        openURL(WhereSurfaceStore.openWhereURL)
    }
}
