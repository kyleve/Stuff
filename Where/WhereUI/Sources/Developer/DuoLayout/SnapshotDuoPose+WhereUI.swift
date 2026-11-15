#if DEBUG
    import SnapshotKit
    import SwiftUI

    extension SnapshotConfiguration.DuoPose {
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
