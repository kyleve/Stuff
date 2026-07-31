import SwiftUI
import WhereSurface

struct WhereMenuBarUnavailableView: View {
    @Environment(\.openURL) private var openURL

    let reason: WhereMenuBarModel.UnavailableReason

    var body: some View {
        VStack(alignment: .leading) {
            Label(title, systemImage: "location.slash")
                .font(.headline)
            Text(description)
                .foregroundStyle(.secondary)
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

    private var title: LocalizedStringResource {
        switch reason {
            case .notPublished:
                .menuBarUnavailableTitle
            case .unreadable, .appGroupUnavailable:
                .menuBarUnavailableFailureTitle
        }
    }

    private var description: LocalizedStringResource {
        switch reason {
            case .notPublished:
                .menuBarUnavailableDescription
            case .unreadable:
                .menuBarUnavailableUnreadable
            case .appGroupUnavailable:
                .menuBarUnavailableAppGroup
        }
    }
}
