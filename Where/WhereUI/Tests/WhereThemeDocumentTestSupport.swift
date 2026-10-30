import BroadwayCore
import Foundation
import SwiftUI
import Testing
import UIKit
import ViewDocumentCore
import ViewDocumentUI
import WhereCore
@testable import WhereUI

/// A red background while active, with an invisible deterministic inactive pose.
@MainActor
func activeThemeBackground() throws -> PreparedWhereThemeDocument {
    var document = themeDocument(appearance: .init(), fallback: .standard)
    var hidden = ViewAnimationDescriptor.Pose.identity
    hidden.opacity = 0
    document.layers.locationsBackground = [.init(schemaVersion: 1, root: .init(
        id: .init(rawValue: "activity-probe"),
        content: .shape(.rectangle),
        modifiers: [.foreground(.color(.rgba(red: 1, green: 0, blue: 0, alpha: 1)))],
        animation: .init(
            from: .identity,
            to: .identity,
            staticPose: hidden,
            duration: 1,
            delay: 0,
            curve: .linear,
            repetition: .forever(autoreverses: false),
        ),
        accessibility: .hidden,
    ))]
    let assets = ViewDocumentAssets(images: [:], symbols: [:])
    return try PreparedWhereThemeDocument(
        validated: ValidatedWhereThemeDocument(document: document, resources: assets.resources),
        assets: assets,
    )
}

@MainActor
func themeBackgroundIsRed(in view: UIView) -> Bool {
    var pixel = [UInt8](repeating: 0, count: 4)
    pixel.withUnsafeMutableBytes { bytes in
        guard let context = CGContext(
            data: bytes.baseAddress,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return }
        context.translateBy(x: -8, y: -view.bounds.midY)
        view.layer.render(in: context)
    }
    return pixel[0] > 240 && pixel[1] < 15 && pixel[2] < 15 && pixel[3] > 240
}

@MainActor
func themeDocument(
    appearance: WhereThemeAppearance,
    fallback: WhereThemeDocument.Fallback,
) -> WhereThemeDocument {
    .init(
        schemaVersion: 1,
        id: .init(rawValue: "test"),
        fallback: fallback,
        appearance: appearance,
        layers: .init(),
    )
}

@MainActor
func resolveTheme(_ document: WhereThemeDocument, traits: BTraits) throws -> WhereStylesheet {
    let validated = try ValidatedWhereThemeDocument(
        document: document,
        resources: .init(images: [], symbols: []),
    )
    var themes = BThemes()
    themes[WhereDocumentTheme.self] = .init(document: validated)
    return BContext(traits: traits, themes: themes).stylesheet(
        WhereStylesheet.self,
        fallback: .default,
    )
}

@MainActor
func verifyThemePatch<Value: Equatable>(
    json: String,
    keyPath: WritableKeyPath<WhereStylesheet, Value>,
    replacement: Value,
) throws {
    let patch = try JSONDecoder().decode(WhereThemeAppearance.self, from: Data(json.utf8))
    #expect(try JSONDecoder()
        .decode(WhereThemeAppearance.self, from: JSONEncoder().encode(patch)) == patch)
    var actual = WhereStylesheet.default
    var expected = actual
    expected[keyPath: keyPath] = replacement
    try patch.apply(
        to: &actual,
        traits: .system,
        appearance: .init(background: .white, dimensionScales: [:]),
        path: "appearance",
    )
    #expect(actual == expected)
}
