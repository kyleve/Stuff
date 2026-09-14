#if canImport(UIKit)
    import Foundation
    import PortholeCore
    import UIKit

    /// The host injects this native source into guarded screenshot evidence; never export it as a
    /// tool.
    @MainActor
    public struct PortholeWindowScreenshotCapture: PortholeScreenshotCapturing {
        public init() {}

        public func capturePNG() throws -> Data {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .filter({ $0.activationState == .foregroundActive })
                .flatMap(\.windows).first(where: \.isKeyWindow)
            else { throw PortholeError.unsupported("No visible application window is available.") }
            var rendered = false
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            let data = renderer.pngData { _ in
                rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            guard rendered
            else {
                throw PortholeError.unsupported("The application window could not be rendered.")
            }
            return data
        }
    }
#endif
