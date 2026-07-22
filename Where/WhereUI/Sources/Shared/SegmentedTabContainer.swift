import SwiftUI
import WhereCore

/// Persisted `UserDefaults` keys for ``SegmentedTabContainer`` selections. A
/// typed source so a key can't silently typo into an untracked default;
/// `@AppStorage` still stores the raw string under the hood.
enum SegmentStoreKey: String {
    case year = "where.segment.year"
    case data = "where.segment.data"
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
/// The container owns only the control + transition; the hosting tab supplies
/// the `NavigationStack`, title, and any toolbar items, and each segment's
/// content view carries its own contextual toolbar/loading.
struct SegmentedTabContainer<Item: SegmentedItem, Content: View>: View {
    @AppStorage private var selection: Item
    private let pickerLabel: String
    private let content: (Item) -> Content

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Index of the segment shown before the latest change, so the slide knows
    /// which way to move. Seeded to the initial segment; refreshed on change.
    @State private var lastIndex: Int

    /// - Parameters:
    ///   - storageKey: Where the selected segment persists across launches.
    ///   - initialSelection: The segment shown on first launch (before any
    ///     persisted choice exists).
    ///   - pickerLabel: The segmented control's accessibility label.
    init(
        storageKey: SegmentStoreKey,
        initialSelection: Item,
        pickerLabel: String,
        @ViewBuilder content: @escaping (Item) -> Content,
    ) {
        _selection = AppStorage(wrappedValue: initialSelection, storageKey.rawValue)
        _lastIndex = State(initialValue: Self.index(of: initialSelection))
        self.pickerLabel = pickerLabel
        self.content = content
    }

    private static func index(of item: Item) -> Int {
        Array(Item.allCases).firstIndex(of: item) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(pickerLabel, selection: $selection) {
                ForEach(Array(Item.allCases), id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, stylesheet.spacing.small)
            .accessibilityIdentifier("where_segmented_control")

            content(selection)
                .id(selection)
                .transition(transition)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(
            reduceMotion ? stylesheet.motion.reducedReveal : stylesheet.motion.segmentTransition,
            value: selection,
        )
        // `lastIndex` still holds the pre-change index while `body` recomputes
        // the transition for the swap, so the slide direction is correct; catch
        // it up afterward for the next change.
        .onChange(of: selection) { _, newValue in
            lastIndex = Self.index(of: newValue)
        }
    }

    /// A directional slide — the incoming segment enters from the side you moved
    /// toward — or a plain crossfade under Reduce Motion.
    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let movingForward = Self.index(of: selection) >= lastIndex
        return .asymmetric(
            insertion: .move(edge: movingForward ? .trailing : .leading)
                .combined(with: .opacity),
            removal: .move(edge: movingForward ? .leading : .trailing)
                .combined(with: .opacity),
        )
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
            ) { segment in
                ContentUnavailableView(segment.title, systemImage: "square.stack")
            }
            .navigationTitle("Segmented")
        }
        .whereBroadwayRoot()
    }
#endif
