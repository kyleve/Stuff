#if DEBUG
    import SnapshotKit
    import SwiftUI

    /// Named synthetic configurations from SnapshotKit's measured Duo profiles.
    enum AdaptiveHistoryPose: String, CaseIterable, Identifiable {
        case outerPortrait
        case outerLandscape
        case innerPortrait
        case innerLandscape
        case tabletop
        case book
        case narrow

        var id: Self {
            self
        }

        var title: String {
            switch self {
                case .outerPortrait: String(localized: .developerDuoOuterPortrait)
                case .outerLandscape: String(localized: .developerDuoOuterLandscape)
                case .innerPortrait: String(localized: .developerDuoInnerPortrait)
                case .innerLandscape: String(localized: .developerDuoInnerLandscape)
                case .tabletop: String(localized: .developerDuoTabletop)
                case .book: String(localized: .developerDuoBook)
                case .narrow: String(localized: .developerDuoNarrow)
            }
        }

        var frame: SnapshotConfiguration.Frame {
            switch self {
                case .outerPortrait: .duoOuterPortrait
                case .outerLandscape: .duoOuterLandscape
                case .innerPortrait, .tabletop: .duoInnerPortrait
                case .innerLandscape, .book: .duoInnerLandscape
                case .narrow: .narrowWindow
            }
        }

        var size: CGSize {
            switch frame.size {
                case let .fixed(size): size
                case .intrinsic, .fullContent, .fullContent2D:
                    preconditionFailure("Adaptive lab profiles must be bounded viewports")
            }
        }

        var regions: [AdaptiveHistoryReservedRegion] {
            switch self {
                case .tabletop:
                    [.init(
                        kind: .division,
                        frame: CGRect(x: 0, y: 455.5, width: 669, height: 40),
                        isActive: true,
                    )]
                case .book:
                    [.init(
                        kind: .division,
                        frame: CGRect(x: 455.5, y: 0, width: 40, height: 669),
                        isActive: true,
                    )]
                case .innerPortrait:
                    [.init(
                        kind: .division,
                        frame: CGRect(x: 0, y: 455.5, width: 669, height: 40),
                        isActive: false,
                    )]
                case .innerLandscape:
                    [.init(
                        kind: .division,
                        frame: CGRect(x: 455.5, y: 0, width: 40, height: 669),
                        isActive: false,
                    )]
                case .outerPortrait, .outerLandscape, .narrow:
                    []
            }
        }
    }
#endif
