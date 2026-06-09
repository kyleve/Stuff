import SwiftUI
import WhereCore

/// Home tab: a passport booklet for the selected year — a bio-data page
/// followed by one stamped page per headline region, flipped through
/// horizontally.
struct PrimaryView: View {
    @Environment(WhereModel.self) private var model

    @State private var showingTimeline = false
    @State private var showingMissingDays = false

    /// Drives the passport's tilt-reactive holographic sheen. Started/stopped
    /// with the view's lifecycle; a no-op on hardware without device motion.
    @State private var tilt = TiltProvider()

    /// Which booklet page is showing. Reset to the bio page when the year
    /// changes, since the new year's region pages may be entirely different.
    @State private var currentPage: BookletPage? = .bio

    /// Where the one-time cover-open intro is in its lifecycle. The cover
    /// renders from the first frame (hiding the load behind it) and is swung
    /// open by the `task` below; Reduce Motion skips it entirely.
    private enum CoverState {
        case closed
        case opened
    }

    @State private var coverState: CoverState = .closed
    @State private var coverAngle: Double = 0
    @State private var coverOpacity: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far each page tilts around its spine while being flipped.
    private static let pageFlipDegrees: Double = -14
    private static let pageFlipPerspective: Double = 0.4
    /// Final swing of the cover-open intro, past edge-on so it reads as a
    /// cover being thrown open rather than folded flat.
    private static let coverOpenDegrees: Double = -120

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.missingDayCount > 0 {
                    MissingDaysBanner(count: model.missingDayCount, tilt: tilt) {
                        showingMissingDays = true
                    }
                    .padding(.horizontal)
                    .padding(.top, UIConstants.Spacings.small)
                    .padding(.bottom, UIConstants.Spacings.medium)
                }
                screen
                    .overlay { coverOverlay }
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
        .task { await openCover() }
        .sheet(isPresented: $showingTimeline) {
            PresenceTimelineView()
                .environment(model)
        }
        .sheet(isPresented: $showingMissingDays) {
            MissingDaysView()
                .environment(model)
        }
    }

    /// The closed cover sitting over the booklet until the intro swings it
    /// open around its spine. Sized to match the pages' footprint.
    @ViewBuilder
    private var coverOverlay: some View {
        if coverState != .opened {
            PassportCover(tilt: tilt)
                .padding(.horizontal)
                .padding(.vertical, UIConstants.Spacings.medium)
                .rotation3DEffect(
                    .degrees(coverAngle),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .leading,
                    perspective: 0.3,
                )
                .opacity(coverOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Play the one-time cover-open intro: hold the closed cover briefly,
    /// swing it open around the spine while it fades, then remove it. Reduce
    /// Motion (or a replayed lifecycle) skips straight to the open booklet.
    private func openCover() async {
        guard coverState == .closed else { return }
        guard !reduceMotion else {
            coverState = .opened
            return
        }
        // Reset in case a previous run was cancelled mid-swing.
        coverAngle = 0
        coverOpacity = 1
        do {
            try await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeInOut(duration: 0.8)) { coverAngle = Self.coverOpenDegrees }
            withAnimation(.easeIn(duration: 0.35).delay(0.45)) { coverOpacity = 0 }
            try await Task.sleep(for: .milliseconds(850))
        } catch {
            // Cancelled (tab switched away mid-intro); replay on next visit.
            return
        }
        coverState = .opened
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

    /// The booklet itself: a horizontally paged scroll of passport pages —
    /// the bio-data page first, then one stamped page per headline region.
    private var content: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.element) { index, page in
                    PassportPage(pageNumber: index + 1, pageCount: pages.count) {
                        pageContent(for: page)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, UIConstants.Spacings.medium)
                    .containerRelativeFrame(.horizontal)
                    // A slight fold around the spine plus a fade as pages
                    // enter and leave, so swiping reads as turning pages.
                    // Reduce Motion keeps the fade but drops the 3D fold.
                    .scrollTransition(axis: .horizontal) { content, phase in
                        content
                            .rotation3DEffect(
                                .degrees(reduceMotion ? 0 : phase.value * Self.pageFlipDegrees),
                                axis: (x: 0, y: 1, z: 0),
                                anchor: .leading,
                                perspective: Self.pageFlipPerspective,
                            )
                            .opacity(1 - abs(phase.value) * 0.25)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentPage)
        .scrollIndicators(.hidden)
        .onChange(of: model.selectedYear) {
            currentPage = .bio
        }
        .accessibilityIdentifier("where_root_title")
    }

    /// The booklet's page order for the loaded year.
    private var pages: [BookletPage] {
        [.bio] + model.ranking.primary.map { .region($0.region) }
    }

    @ViewBuilder
    private func pageContent(for page: BookletPage) -> some View {
        switch page {
            case .bio:
                PassportBioPage(tilt: tilt)
            case let .region(region):
                if let index = model.ranking.primary.firstIndex(where: { $0.region == region }) {
                    RegionSummaryCard(
                        regionDays: model.ranking.primary[index],
                        caption: caption(forRank: index),
                        yearLength: model.daysInSelectedYear,
                        year: model.selectedYear,
                        tilt: tilt,
                    )
                }
        }
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

/// Identity of one page in the booklet pager, used for scroll-position
/// tracking.
private enum BookletPage: Hashable {
    case bio
    case region(Region)
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
