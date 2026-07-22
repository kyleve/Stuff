import SwiftUI
import WhereCore

/// Persisted `UserDefaults` keys for ``SegmentedTabContainer`` selections. A
/// typed source so a key can't silently typo into an untracked default;
/// `@AppStorage` still stores the raw string under the hood.
enum SegmentStoreKey: String {
    case year = "where.segment.year"
    case data = "where.segment.data"

    /// Distinct accessibility id for each tab's segmented control.
    var accessibilityID: String {
        switch self {
            case .year: "where_year_segmented_control"
            case .data: "where_data_segmented_control"
        }
    }
}

/// A segment a ``SegmentedTabContainer`` switches between: a `String`-backed
/// enum whose cases are the segments (so the selection round-trips through
/// `@AppStorage`), each carrying a localized `title` for the control.
protocol SegmentedItem: CaseIterable, Hashable, RawRepresentable where RawValue == String {
    /// The segmented-control label for this segment.
    var title: String { get }
}

/// The shared switching chrome for the Your Year and Your Data tabs: a
/// segmented control over `Item`'s cases whose selected segment is remembered
/// across launches (`@AppStorage`, keyed by a typed ``SegmentStoreKey``),
/// driving a content builder. Swapping segments animates with a
/// Reduce-Motion-aware directional slide (a plain crossfade when reduced).
///
/// **All segments stay mounted** (only the selected one is visible and
/// interactive), so switching preserves each segment's state — scroll position,
/// filters, loaded data — rather than tearing it down and reloading. The
/// builder receives whether a segment is currently selected so a content view
/// can, e.g., contribute its toolbar items only while active.
///
/// The container owns only the control + slide; the hosting tab supplies the
/// `NavigationStack`, title, and any tab-level toolbar items.
struct SegmentedTabContainer<Item: SegmentedItem, Content: View>: View {
    @AppStorage private var selection: Item
    private let storageKey: SegmentStoreKey
    private let pickerLabel: String
    private let content: (Item, Bool) -> Content

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - storageKey: Where the selected segment persists across launches.
    ///   - initialSelection: The segment shown on first launch (before any
    ///     persisted choice exists).
    ///   - pickerLabel: The segmented control's accessibility label.
    ///   - content: Builds a segment's view; the `Bool` is whether it is the
    ///     currently selected segment.
    init(
        storageKey: SegmentStoreKey,
        initialSelection: Item,
        pickerLabel: String,
        @ViewBuilder content: @escaping (Item, Bool) -> Content,
    ) {
        _selection = AppStorage(wrappedValue: initialSelection, storageKey.rawValue)
        self.storageKey = storageKey
        self.pickerLabel = pickerLabel
        self.content = content
    }

    private var segments: [Item] {
        Array(Item.allCases)
    }

    private func index(of item: Item) -> Int {
        segments.firstIndex(of: item) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(pickerLabel, selection: $selection) {
                ForEach(segments, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, stylesheet.spacing.small)
            .accessibilityIdentifier(storageKey.accessibilityID)

            slidingContent
        }
    }

    /// All segments mounted in a `ZStack`; the selected one sits at rest while
    /// the others are offset one container-width to their side, so changing the
    /// selection slides them across. Only the selected segment is visible,
    /// hit-testable, and exposed to VoiceOver. Under Reduce Motion nothing moves
    /// horizontally — the change is a plain opacity crossfade.
    private var slidingContent: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(segments, id: \.self) { item in
                    content(item, item == selection)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .opacity(item == selection ? 1 : 0)
                        .offset(x: offset(for: item, width: proxy.size.width))
                        .allowsHitTesting(item == selection)
                        .accessibilityHidden(item != selection)
                }
            }
            .animation(
                reduceMotion
                    ? stylesheet.motion.reducedReveal
                    : stylesheet.motion.segmentTransition,
                value: selection,
            )
        }
    }

    private func offset(for item: Item, width: CGFloat) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return CGFloat(index(of: item) - index(of: selection)) * width
    }
}

#if DEBUG
    /// A throwaway segment set so the preview exercises the control + slide
    /// without depending on a real tab's segments.
    private enum PreviewSegment: String, CaseIterable, SegmentedItem {
        case first
        case second
        case third

        var title: String {
            switch self {
                case .first: "First"
                case .second: "Second"
                case .third: "Third"
            }
        }
    }

    #Preview {
        NavigationStack {
            SegmentedTabContainer(
                storageKey: .year,
                initialSelection: PreviewSegment.first,
                pickerLabel: "Preview segments",
            ) { segment, _ in
                ContentUnavailableView(segment.title, systemImage: "square.stack")
            }
            .navigationTitle("Segmented")
        }
        .whereBroadwayRoot()
    }
#endif
