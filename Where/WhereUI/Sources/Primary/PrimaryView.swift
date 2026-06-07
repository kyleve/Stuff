import SwiftUI
import WhereCore

/// Home tab: the regions you spend the most days in for the selected year,
/// shown as prominent Liquid Glass cards.
struct PrimaryView: View {
    @Environment(WhereModel.self) private var model

    @State private var showingTimeline = false
    @State private var showingMissingDays = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.missingDayCount > 0 {
                    MissingDaysBanner(count: model.missingDayCount) {
                        showingMissingDays = true
                    }
                    .padding(.horizontal)
                    .padding(.bottom, UIConstants.Spacings.medium)
                }
                screen
            }
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
            .sheet(isPresented: $showingMissingDays) {
                MissingDaysView()
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
                    // Distinguish "nothing tracked at all" from "tracked days
                    // exist, but only in non-headline regions" (e.g. all in
                    // `.other`) — otherwise the latter wrongly reads as empty.
                    if model.trackedDayCount == 0 {
                        emptyState
                    } else {
                        elsewhereOnlyState
                    }
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

    private var elsewhereOnlyState: some View {
        ContentUnavailableView {
            Label(Strings.primaryElsewhereOnlyTitle, systemImage: "globe.americas")
        } description: {
            Text(Strings.primaryElsewhereOnlyDescription(count: model.trackedDayCount))
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

/// A tappable Liquid Glass warning that some days this year aren't logged yet,
/// shown atop the Primary tab. Opens `MissingDaysView` to backfill them.
private struct MissingDaysBanner: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: UIConstants.Spacings.large) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: UIConstants.Spacings.xxSmall) {
                    Text(Strings.missingBannerTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(Strings.missingBannerSubtitle(count: count))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: UIConstants.Spacings.small)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(UIConstants.Padding.compactCard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular.tint(.orange.opacity(0.18)),
                in: RoundedRectangle(
                    cornerRadius: UIConstants.CornerRadius.compactCard,
                    style: .continuous,
                ),
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("where_missing_days_banner")
        .accessibilityHint(Strings.missingBannerAccessibilityHint)
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

    #Preview("Missing days") {
        PrimaryView()
            .environment(PreviewSupport.missingDaysModel())
    }
#endif
