#if canImport(UIKit)
    import UIKit
#endif

/// The logged-in shell chosen from the device family, not the current window
/// width, so an iPad keeps its split-view navigation as the window resizes.
enum MainInterfaceStyle {
    case tabs
    case split

    @MainActor
    static var current: Self {
        #if targetEnvironment(macCatalyst)
            .split
        #elseif canImport(UIKit)
            UIDevice.current.userInterfaceIdiom == .pad ? .split : .tabs
        #else
            .split
        #endif
    }
}
