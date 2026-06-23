import SwiftUI
import WhereCore

/// Elsewhere tab: every region outside your primary spots, shown as compact
/// Liquid Glass cards for the selected year.
struct SecondaryView: View {
    @Environment(WhereSession.self) private var session

    /// Reverse-geocoded "where" teaser per region, loaded asynchronously so
    /// each card can show the place you turned up most. Empty in
    /// previews/tests (no raw samples) and until the lookups resolve.
    @State private var placeNames: [Region: String] = [:]

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
        .task(id: session.report) { await loadPlaceNames() }
    }

    /// Pick each secondary region's most-sampled spot and reverse-geocode it,
    /// so the cards gain a "Paris, France"-style teaser. One geocode per
    /// region; results are cached by `LocationNamer`.
    private func loadPlaceNames() async {
        let coordinates = await session.representativeCoordinates()
        var names: [Region: String] = [:]
        for item in session.ranking.secondary {
            guard let coordinate = coordinates[item.region] else { continue }
            names[item.region] = await LocationNamer.shared.name(for: coordinate)
        }
        // Geocoding can outlive the report/year that started it (LocationNamer's
        // in-flight tasks don't observe cancellation), so a stale run could
        // publish last and show the wrong year's teasers. Drop it if superseded.
        guard !Task.isCancelled else { return }
        placeNames = names
    }

    @ViewBuilder
    private var screen: some View {
        switch session.loadState {
            case .loading where session.report == nil:
                ProgressView(Strings.secondaryLoading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView {
                    Label(Strings.loadErrorTitle, systemImage: "exclamationmark.icloud")
                } description: {
                    Text(message)
                }
            case .idle, .loaded, .loading:
                if session.ranking.secondary.isEmpty {
                    emptyState
                } else {
                    content
                }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UIConstants.Spacings.xLarge) {
                Text(Strings.secondaryHeader(year: session.selectedYear))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                GlassEffectContainer(spacing: UIConstants.Spacings.large) {
                    VStack(spacing: UIConstants.Spacings.large) {
                        ForEach(session.ranking.secondary) { item in
                            NavigationLink {
                                RegionDaysView(region: item.region)
                            } label: {
                                RegionSummaryCard(
                                    regionDays: item,
                                    caption: caption(for: item),
                                    places: placeNames[item.region],
                                    compact: true,
                                    yearLength: session.daysInSelectedYear,
                                    year: session.selectedYear,
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
            .environment(PreviewSupport.loadedSession())
    }

    #Preview("Empty") {
        SecondaryView()
            .environment(PreviewSupport.emptySession())
    }
#endif
