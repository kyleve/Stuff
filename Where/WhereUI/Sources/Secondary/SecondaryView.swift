import SwiftUI
import WhereCore

/// Elsewhere tab: every region outside your primary spots, shown as compact
/// Liquid Glass cards for the selected year.
struct SecondaryView: View {
    @Environment(WhereModel.self) private var model

    var body: some View {
        NavigationStack {
            screen
                .navigationTitle(Strings.secondaryTitle)
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
                ProgressView(Strings.secondaryLoading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView {
                    Label(Strings.loadErrorTitle, systemImage: "exclamationmark.icloud")
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
                Text(Strings.secondaryHeader(year: model.selectedYear))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                GlassEffectContainer(spacing: UIConstants.Spacings.large) {
                    VStack(spacing: UIConstants.Spacings.large) {
                        ForEach(model.ranking.secondary) { item in
                            NavigationLink {
                                RegionDaysView(region: item.region)
                            } label: {
                                RegionSummaryCard(
                                    regionDays: item,
                                    caption: caption(for: item),
                                    compact: true,
                                    yearLength: model.daysInSelectedYear,
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(Strings.secondaryEmptyTitle, systemImage: "globe.americas")
        } description: {
            Text(Strings.secondaryEmptyDescription)
        }
    }

    /// Light whimsy for the briefest stays.
    private func caption(for item: RegionDays) -> String? {
        item.days <= 3 ? Strings.secondaryCaptionPassingThrough : nil
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
