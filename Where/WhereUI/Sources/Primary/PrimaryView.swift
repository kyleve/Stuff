import SwiftUI
import WhereCore

/// Home tab: the regions you spend the most days in for the selected year,
/// shown as prominent Liquid Glass cards.
struct PrimaryView: View {
    @Environment(WhereModel.self) private var model

    var body: some View {
        NavigationStack {
            screen
                .navigationTitle("Where")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        YearSelector()
                    }
                }
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch model.loadState {
            case .loading where model.report == nil:
                ProgressView("Charting your year…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Couldn't load your year", systemImage: "exclamationmark.icloud")
                } description: {
                    Text(message)
                }
            default:
                if model.ranking.primary.isEmpty {
                    emptyState
                } else {
                    content
                }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 16) {
                        ForEach(
                            Array(model.ranking.primary.enumerated()),
                            id: \.element.id,
                        ) { index, item in
                            RegionSummaryCard(regionDays: item, caption: caption(forRank: index))
                        }
                    }
                }
            }
            .padding()
        }
        .accessibilityIdentifier("where_root_title")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Where have you been in \(model.selectedYear)?")
                .font(.largeTitle.bold())
            Text(verbatim: "\(model.trackedDayCount) days on the map so far")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(noTravelsTitle, systemImage: "map")
        } description: {
            Text("Turn on tracking or add a day in Settings and your top spots will land here.")
        }
    }

    private var noTravelsTitle: String {
        "No travels logged for \(model.selectedYear)"
    }

    /// Playful rank labels for the top regions.
    private func caption(forRank rank: Int) -> String? {
        switch rank {
            case 0: "Home base"
            case 1: "Second home"
            default: nil
        }
    }
}

#if DEBUG
    #Preview("Loaded") {
        PrimaryView()
            .environment(PreviewSupport.loadedModel())
    }

    #Preview("Empty") {
        PrimaryView()
            .environment(PreviewSupport.emptyModel())
    }
#endif
