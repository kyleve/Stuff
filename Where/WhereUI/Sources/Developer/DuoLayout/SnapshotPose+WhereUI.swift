#if DEBUG
    import SnapshotKit
    import SwiftUI

    extension SnapshotConfiguration.Pose {
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

        var regions: [AdaptivePaneReservedRegion] {
            reservedRegions.map { region in
                let kind: AdaptivePaneReservedRegion.Kind = switch region.kind {
                    case .division: .division
                    case .occlusion: .occlusion
                }
                return .init(
                    kind: kind,
                    frame: region.frame,
                    isActive: region.isActive,
                )
            }
        }
    }
#endif
