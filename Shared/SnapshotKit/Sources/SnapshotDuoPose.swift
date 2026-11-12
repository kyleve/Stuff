import CoreGraphics
import Foundation

extension SnapshotConfiguration {
    /// Synthetic container geometry for adaptive previews, captures, and hosted tests.
    /// These profiles do not change the simulator's native folding pose.
    public enum DuoPose: String, CaseIterable, Identifiable, Sendable {
        case outerPortrait
        case outerLandscape
        case innerPortrait
        case innerLandscape
        case tabletop
        case book
        case narrow

        public var title: String {
            switch self {
                case .outerPortrait: String(localized: .duoOuterPortrait)
                case .outerLandscape: String(localized: .duoOuterLandscape)
                case .innerPortrait: String(localized: .duoInnerPortrait)
                case .innerLandscape: String(localized: .duoInnerLandscape)
                case .tabletop: String(localized: .duoTabletop)
                case .book: String(localized: .duoBook)
                case .narrow: String(localized: .duoNarrow)
            }
        }

        public var id: Self {
            self
        }

        public struct ReservedRegion: Hashable, Sendable {
            public enum Kind: Hashable, Sendable {
                case division
                case occlusion
            }

            public let kind: Kind
            public let frame: CGRect
            public let isActive: Bool
        }

        public var frame: Frame {
            switch self {
                case .outerPortrait: .duoOuterPortrait
                case .outerLandscape: .duoOuterLandscape
                case .innerPortrait, .tabletop: .duoInnerPortrait
                case .innerLandscape, .book: .duoInnerLandscape
                case .narrow: .narrowWindow
            }
        }

        public var size: CGSize {
            switch frame.size {
                case let .fixed(size): size
                case .intrinsic, .fullContent, .fullContent2D:
                    preconditionFailure("Synthetic poses require bounded viewports")
            }
        }

        public var reservedRegions: [ReservedRegion] {
            switch self {
                case .innerPortrait, .tabletop:
                    [.init(
                        kind: .division,
                        frame: CGRect(x: 0, y: 455.5, width: 669, height: 40),
                        isActive: self == .tabletop,
                    )]
                case .innerLandscape, .book:
                    [.init(
                        kind: .division,
                        frame: CGRect(x: 455.5, y: 0, width: 40, height: 669),
                        isActive: self == .book,
                    )]
                case .outerPortrait, .outerLandscape, .narrow: []
            }
        }
    }
}
