import StuffCore
import SwiftUI
import WhereCore

/// Home tab: the regions you spend the most days in for the selected year,
/// shown as prominent Liquid Glass cards.
struct PrimaryView: View {
    @Environment(WhereSession.self) private var session

    @State private var showingTimeline = false
    @State private var showingMissingDays = false

    /// Drives the passport's tilt-reactive holographic sheen. Started/stopped
    /// with the view's lifecycle; a no-op on hardware without device motion.
    @State private var tilt = TiltProvider()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PassportMasthead(title: LocalizedStrings.Primary.title.localized, tilt: tilt)
                    .padding(.horizontal)
                    .padding(.top, UIConstants.Spacings.small)
                    .padding(.bottom, UIConstants.Spacings.medium)

                if session.missingDayCount > 0 {
                    MissingDaysBanner(count: session.missingDayCount, tilt: tilt) {
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
                            LocalizedStrings.Primary.timeline.localized,
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
                .environment(session)
        }
        .sheet(isPresented: $showingMissingDays) {
            MissingDaysView()
                .environment(session)
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
        switch session.loadState {
            case .loading where session.report == nil:
                ProgressView(LocalizedStrings.Primary.loading.localized)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView {
                    Label(
                        LocalizedStrings.Common.loadErrorTitle.localized,
                        systemImage: "exclamationmark.icloud",
                    )
                } description: {
                    Text(message)
                }
            case .idle, .loaded, .loading:
                if session.ranking.primary.isEmpty {
                    // Distinguish "nothing tracked at all" from "tracked days
                    // exist, but only in non-headline regions" (e.g. all in
                    // `.other`) — otherwise the latter wrongly reads as empty.
                    if session.trackedDayCount == 0 {
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
                    ForEach(session.ranking.primary) { item in
                        RegionSummaryCard(
                            regionDays: item,
                            yearLength: session.daysInSelectedYear,
                            year: session.selectedYear,
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
            Label(
                LocalizedStrings.Primary.emptyTitle(year: session.selectedYear).localized,
                systemImage: "map",
            )
        } description: {
            Text.localized(LocalizedStrings.Primary.emptyDescription)
        }
    }

    private var elsewhereOnlyState: some View {
        ContentUnavailableView {
            Label(
                LocalizedStrings.Primary.elsewhereOnlyTitle.localized,
                systemImage: "globe.americas",
            )
        } description: {
            Text
                .localized(LocalizedStrings.Primary
                    .elsewhereOnlyDescription(count: session.trackedDayCount))
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Lateral position of the glint, normalized `-1...1`. Pinned to a gentle
    /// off-center value when motion is unavailable or reduced.
    private var glintRoll: Double {
        guard !reduceMotion, let roll = tilt?.roll else { return 0.2 }
        return min(1, max(-1, roll))
    }

    var body: some View {
        let wordmark = Text(verbatim: title.uppercased())
            .font(.system(
                size: UIConstants.Size.mastheadFontSize,
                weight: .heavy,
                design: .serif,
            ))
            .tracking(2)

        return wordmark
            .foregroundStyle(goldFoil)
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.95), .clear],
                    startPoint: UnitPoint(x: glintRoll * 0.5 - 0.1, y: 0),
                    endPoint: UnitPoint(x: glintRoll * 0.5 + 0.6, y: 1),
                )
                .blendMode(.plusLighter)
            }
            .mask { wordmark }
            .shadow(
                color: .black.opacity(0.45),
                radius: UIConstants.Spacings.xSmall,
                y: UIConstants.Spacings.xxSmall,
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(title)
    }

    /// Brushed-gold gradient that reads as embossed gilt on the dark cover.
    private var goldFoil: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.93, blue: 0.7),
                Color(red: 0.86, green: 0.66, blue: 0.32),
                Color(red: 1.0, green: 0.9, blue: 0.66),
                Color(red: 0.72, green: 0.52, blue: 0.24),
            ],
            startPoint: .top,
            endPoint: .bottom,
        )
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

                Text.localized(LocalizedStrings.MissingBanner.compact(count: count))
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
        .accessibilityLabel(LocalizedStrings.MissingBanner.compact(count: count).localized)
        .accessibilityHint(LocalizedStrings.MissingBanner.accessibilityHint.localized)
    }
}

#if DEBUG
    #Preview("Loaded") {
        PrimaryView()
            .environment(PreviewSupport.loadedSession())
    }

    #Preview("Empty") {
        PrimaryView()
            .environment(PreviewSupport.emptySession())
    }

    #Preview("Missing days") {
        PrimaryView()
            .environment(PreviewSupport.missingDaysSession())
    }

    #Preview("Elsewhere only") {
        PrimaryView()
            .environment(PreviewSupport.elsewhereOnlySession())
    }
#endif
