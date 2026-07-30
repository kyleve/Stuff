#if DEBUG
    import SwiftUI

    /// A WhereUI screen that declares its Flyover representation beside its view.
    @MainActor
    protocol WhereFlyoverProviding: View {
        static var flyoverData: WhereFlyoverData { get }
    }

    extension WhereFlyoverProviding {
        static var flyoverID: WhereFlyoverScreenID {
            WhereFlyoverScreenID(Self.self)
        }
    }
#endif
