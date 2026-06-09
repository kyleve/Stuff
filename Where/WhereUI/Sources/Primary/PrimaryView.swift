import SwiftUI
import WhereCore

/// Home tab: the regions you spend the most days in for the selected year,
/// shown as prominent Liquid Glass cards.
struct PrimaryView: View {
    @Environment(WhereModel.self) private var model

    @State private var showingTimeline = false
    @State private var showingMissingDays = false

    /// Drives the passport's tilt-reactive holographic sheen. Started/stopped
    /// with the view's lifecycle; a no-op on hardware without device motion.
    @State private var tilt = TiltProvider()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PassportMasthead(title: Strings.primaryTitle, tilt: tilt)
                    .padding(.horizontal)
                    .padding(.top, UIConstants.Spacings.small)
                    .padding(.bottom, UIConstants.Spacings.medium)

                if model.missingDayCount > 0 {
                    MissingDaysBanner(count: model.missingDayCount, tilt: tilt) {
                        showingMissingDays = true
                    }
                    .padding(.horizontal)
                    .padding(.bottom, UIConstants.Spacings.medium)
                }
                screen
            }
            .background(elevatedBackground)
            .environment(\.colorScheme, .dark)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
        }
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
        .sheet(isPresented: $showingTimeline) {
            PresenceTimelineView()
                .environment(model)
        }
        .sheet(isPresented: $showingMissingDays) {
            MissingDaysView()
                .environment(model)
        }
    }

    /// A deep, near-black gradient that makes the Primary tab read like a
    /// passport cover, so the glass cards and their foil sheen feel elevated
    /// off the page. Forced dark (see `colorScheme` above) regardless of the
    /// system appearance.
    private var elevatedBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.08, blue: 0.13),
                Color(red: 0.02, green: 0.02, blue: 0.05),
            ],
            startPoint: .top,
            endPoint: .bottom,
        )
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
                            year: model.selectedYear,
                            tilt: tilt,
                        )
                    }
                }
            }
            .padding()
        }
        .accessibilityIdentifier("where_root_title")
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

/// The Primary tab's masthead: the app wordmark embossed in gold foil that
/// catches a moving specular glint as the device tilts, like the gilt title on
/// a passport cover. Falls back to a fixed, gentle highlight under Reduce
/// Motion or on hardware without device motion.
private struct PassportMasthead: View {
    let title: String
    var tilt: TiltProvider?

    var body: some View {
        Text(verbatim: title.uppercased())
            .font(.system(
                size: UIConstants.Size.mastheadFontSize,
                weight: .heavy,
                design: .serif,
            ))
            .tracking(2)
            .goldFoil(tilt: tilt)
            .shadow(
                color: .black.opacity(0.45),
                radius: UIConstants.Spacings.xSmall,
                y: UIConstants.Spacings.xxSmall,
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(title)
    }
}

/// A slim, tappable pill inviting you to log the days that don't have a
/// location yet, shown atop the Primary tab. Twinkles and catches the same
/// holographic foil as the cards so it reads as an invitation, not an alarm.
/// Opens `MissingDaysView` to backfill them.
private struct MissingDaysBanner: View {
    let count: Int
    var tilt: TiltProvider?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: UIConstants.Spacings.medium) {
                Image(systemName: "sparkles")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                    .accessibilityHidden(true)

                Text(Strings.missingBannerCompact(count: count))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: UIConstants.Spacings.small)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, UIConstants.Spacings.medium)
            .padding(.horizontal, UIConstants.Spacings.xLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.orange.opacity(0.22)), in: Capsule())
            .holographicSheen(
                roll: tilt?.roll ?? 0,
                pitch: tilt?.pitch ?? 0,
                in: Capsule(),
                tint: .orange,
                intensity: 0.7,
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("where_missing_days_banner")
        .accessibilityLabel(Strings.missingBannerCompact(count: count))
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
