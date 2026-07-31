import SnapshotKit
import SwiftUI
import WhereCore

/// Combined Mac widget content: today's observed regions beside year-to-date
/// day counts, rendered entirely from the app-published snapshot.
public struct MacSummaryWidgetView: View {
    public enum Layout: Sendable {
        case compact
        case wide
    }

    private let snapshot: WidgetSnapshot
    private let layout: Layout

    public init(snapshot: WidgetSnapshot, layout: Layout) {
        self.snapshot = snapshot
        self.layout = layout
    }

    @Environment(\.stylesheet) private var stylesheet

    public var body: some View {
        switch layout {
            case .compact:
                VStack(spacing: stylesheet.spacing.small) {
                    TodayWidgetView(snapshot: snapshot)
                    Divider()
                    YearTotalsWidgetView(snapshot: snapshot, maxRows: 1)
                }
            case .wide:
                HStack(spacing: stylesheet.spacing.medium) {
                    TodayWidgetView(snapshot: snapshot)
                    Divider()
                    YearTotalsWidgetView(snapshot: snapshot, maxRows: 3)
                }
        }
    }
}

#if DEBUG
    extension MacSummaryWidgetView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            let snapshot = PreviewSupport.sampleWidgetSnapshot(
                dayRegions: [.california],
                totals: [.california: 132, .newYork: 41, .canada: 9],
            )
            return [
                whereSnapshot(
                    name: "Wide",
                    configurations: SnapshotConfiguration.combinations(
                        devices: [
                            .init(
                                name: "MacMedium",
                                size: .fixed(CGSize(width: 338, height: 158)),
                            ),
                        ],
                        colorSchemes: [.light, .dark],
                    ),
                    settle: .immediate,
                ) {
                    MacSummaryWidgetView(snapshot: snapshot, layout: .wide)
                },
                whereSnapshot(
                    name: "Compact",
                    configurations: SnapshotConfiguration.combinations(
                        devices: [
                            .init(
                                name: "MacSmall",
                                size: .fixed(CGSize(width: 158, height: 158)),
                            ),
                        ],
                        colorSchemes: [.light, .dark],
                    ),
                    settle: .immediate,
                ) {
                    MacSummaryWidgetView(snapshot: snapshot, layout: .compact)
                },
            ]
        }
    }

    #Preview {
        MacSummaryWidgetView.snapshotPreviews
    }
#endif

#if DEBUG
    extension MacSummaryWidgetView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            MacSummaryWidgetView.self,
            title: "Mac Summary Widget",
            viewport: .fixed(CGSize(width: 338, height: 158)),
            navigationContainer: .none,
        )
    }
#endif
