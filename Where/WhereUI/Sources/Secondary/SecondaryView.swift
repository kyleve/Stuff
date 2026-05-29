import SwiftUI
import WhereCore

/// Elsewhere tab: every region outside your primary spots, shown as compact
/// Liquid Glass cards for the selected year.
struct SecondaryView: View {
    @Environment(WhereModel.self) private var model

    var body: some View {
        NavigationStack {
            screen
                .navigationTitle("Elsewhere")
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
                ProgressView("Retracing your steps…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Couldn't load your year", systemImage: "exclamationmark.icloud")
                } description: {
                    Text(message)
                }
            default:
                if model.ranking.secondary.isEmpty {
                    emptyState
                } else {
                    content
                }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UIConstants.Spacings.xLarge) {
                Text(verbatim: "Everywhere else you turned up in \(model.selectedYear).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                GlassEffectContainer(spacing: UIConstants.Spacings.large) {
                    VStack(spacing: UIConstants.Spacings.large) {
                        ForEach(model.ranking.secondary) { item in
                            RegionSummaryCard(
                                regionDays: item,
                                caption: caption(for: item),
                                compact: true,
                                yearLength: model.daysInSelectedYear,
                            )
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nowhere else logged", systemImage: "globe.americas")
        } description: {
            Text(
                "Spend a day outside your top spots — or log a trip in Settings — and it'll appear here.",
            )
        }
    }

    /// Light whimsy for the briefest stays.
    private func caption(for item: RegionDays) -> String? {
        item.days <= 3 ? "Just passing through" : nil
    }
}

#if DEBUG
    #Preview("Loaded") {
        SecondaryView()
            .environment(PreviewSupport.loadedModel())
    }

    #Preview("Empty") {
        SecondaryView()
            .environment(PreviewSupport.emptyModel())
    }
#endif
