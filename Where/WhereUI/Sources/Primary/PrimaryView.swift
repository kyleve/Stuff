import SwiftUI
import WhereCore

/// Home tab: the regions you spend the most days in for the selected year,
/// shown as prominent Liquid Glass cards.
struct PrimaryView: View {
    @Environment(WhereModel.self) private var model

    @State private var showingTimeline = false

    var body: some View {
        NavigationStack {
            screen
                .navigationTitle(Strings.primaryTitle)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingTimeline = true
                        } label: {
                            Label(
                                Strings.primaryTimeline,
                                systemImage: "calendar.day.timeline.left",
                            )
                        }
                        .accessibilityIdentifier("where_timeline_button")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        YearSelector()
                    }
                }
                .sheet(isPresented: $showingTimeline) {
                    PresenceTimelineView()
                        .environment(model)
                }
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch model.loadState {
            case .loading where model.report == nil:
                ProgressView(Strings.primaryLoading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView {
                    Label(Strings.loadErrorTitle, systemImage: "exclamationmark.icloud")
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
            VStack(alignment: .leading, spacing: UIConstants.Spacings.xxxLarge) {
                header
                GlassEffectContainer(spacing: UIConstants.Spacings.xxLarge) {
                    VStack(spacing: UIConstants.Spacings.xxLarge) {
                        ForEach(
                            Array(model.ranking.primary.enumerated()),
                            id: \.element.id,
                        ) { index, item in
                            RegionSummaryCard(
                                regionDays: item,
                                caption: caption(forRank: index),
                                yearLength: model.daysInSelectedYear,
                            )
                        }
                    }
                }
            }
            .padding()
        }
        .accessibilityIdentifier("where_root_title")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacings.xSmall) {
            Text(Strings.primaryHeaderTitle(year: model.selectedYear))
                .font(.largeTitle.bold())
            Text(Strings.primaryHeaderSubtitle(count: model.trackedDayCount))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(Strings.primaryEmptyTitle(year: model.selectedYear), systemImage: "map")
        } description: {
            Text(Strings.primaryEmptyDescription)
        }
    }

    /// Playful rank labels for the top regions.
    private func caption(forRank rank: Int) -> String? {
        switch rank {
            case 0: Strings.primaryCaptionHomeBase
            case 1: Strings.primaryCaptionSecondHome
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
