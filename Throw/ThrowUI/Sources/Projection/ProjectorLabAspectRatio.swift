#if DEBUG
    import CoreGraphics
    import Foundation

    enum ProjectorLabAspectRatio: String, CaseIterable, Hashable {
        case sixteenByNine
        case sixteenByTen
        case fourByThree

        var ratio: CGFloat {
            switch self {
                case .sixteenByNine: 16 / 9
                case .sixteenByTen: 16 / 10
                case .fourByThree: 4 / 3
            }
        }

        var title: LocalizedStringResource {
            switch self {
                case .sixteenByNine: .projectorLabAspectWidescreen
                case .sixteenByTen: .projectorLabAspectComputer
                case .fourByThree: .projectorLabAspectStandard
            }
        }
    }
#endif
