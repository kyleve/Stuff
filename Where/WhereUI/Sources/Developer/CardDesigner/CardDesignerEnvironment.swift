#if DEBUG
    import SwiftUI

    extension EnvironmentValues {
        /// Root-owned designer state used by the Settings studio.
        @Entry var cardDesignerModel: CardDesignerModel?

        /// The session-only configuration applied to real cards outside the
        /// studio. `nil` keeps the production stylesheet untouched.
        @Entry var cardDesignerConfiguration: CardDesignerConfiguration?
    }
#endif
