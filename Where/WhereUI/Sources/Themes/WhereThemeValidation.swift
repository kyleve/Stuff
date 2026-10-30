import Foundation
import ViewDocumentCore

/// Validation runs before a document can enter Broadway's stylesheet cache.
enum WhereThemeValidation {
    static func validate(_ value: Double, path: String) throws {
        let field = path.split(separator: ".").last.map(String.init)?.lowercased() ?? path
        let signed = ["offset", "rotation", "roll", "pitch", "spacing", "indent", "tracking"]
            .contains { field.contains($0) }
        let fraction = ["opacity", "fraction", "tintmix"].contains { field.contains($0) }
        let density = field.contains("ringspacing") || field == "hatchspacing" || field == "contourspacing"
            || field == "preferredcellsize" ||
            (field == "spacing" && (path.contains("securityBorder") || path.contains(".border.")))
        if density && (!value.isFinite || value < 2) {
            throw WhereThemeValidationError(
                path: path,
                reason: "Pattern spacing must be at least two points",
            )
        }
        if field == "bounce" {
            guard value.isFinite, (-1 ... 1).contains(value) else {
                throw WhereThemeValidationError(path: path, reason: "Invalid spring bounce")
            }
            return
        }
        if field.contains("duration") || field == "delay" {
            guard value.isFinite, (0 ... 60).contains(value) else {
                throw WhereThemeValidationError(
                    path: path,
                    reason: "Presentation timing exceeds sixty seconds",
                )
            }
            return
        }
        let range: ClosedRange<Double> = fraction ? 0 ... 1 :
            (signed ? -10000 ... 10000 : 0 ... 10000)
        guard value.isFinite, range.contains(value) else {
            throw WhereThemeValidationError(
                path: path,
                reason: "Value is outside the supported range \(range)",
            )
        }
    }

    static func validate(
        _ value: WhereThemeAppearance.CardStyle.Typography.Size,
        path: String,
    ) throws {
        switch value {
            case let .fixed(points):
                guard points.isFinite, (1 ... 1000).contains(points) else {
                    throw WhereThemeValidationError(path: path, reason: "Invalid fixed font size")
                }
            case .semantic: break
        }
    }

    static func validate(_: Bool, path _: String) throws {}
    static func validate(_ values: [Double], path: String) throws {
        guard values.count <= 64 else { throw WhereThemeValidationError(
            path: path,
            reason: "Too many values",
        ) }
        for value in values {
            try validate(value, path: path)
        }
    }

    static func validate(_ value: WhereThemeSize, path: String) throws {
        let isOffset = path.lowercased().contains("offset")
        try validate(value.width, path: path + (isOffset ? ".offsetX" : ".width"))
        try validate(value.height, path: path + (isOffset ? ".offsetY" : ".height"))
    }

    static func validate(_ value: WhereThemePoint, path: String) throws {
        try validate(value.x, path: path + ".offsetX")
        try validate(value.y, path: path + ".offsetY")
    }

    static func validate(_ value: ViewColorDescriptor, path: String) throws {
        try validateModifier(.foreground(.color(value)), path: path)
    }

    static func validate(_ value: ViewFontDescriptor, path: String) throws {
        try validateModifier(.font(value), path: path)
    }

    private static func validateModifier(_ value: ViewModifierDescriptor, path: String) throws {
        do {
            _ = try ValidatedViewDocument(document: .init(schemaVersion: 1, root: .init(
                id: .init(rawValue: path),
                content: .text(""),
                modifiers: [value],
                animation: nil,
                accessibility: .hidden,
            )), resources: .init(images: [], symbols: []), limits: .standard)
        } catch let error as ViewDocumentValidationError {
            throw WhereThemeValidationError(path: path, underlying: error)
        }
    }

    static func validate(_ value: WhereThemeAnimation, path: String) throws {
        let duration: Double
        switch value {
            case let .linear(seconds), let .easeIn(seconds), let .easeOut(seconds),
                 let .easeInOut(seconds): duration =
            seconds
            case let .spring(seconds, bounce):
                duration = seconds
                guard bounce.isFinite,
                      (-1 ... 1).contains(bounce)
                else { throw WhereThemeValidationError(
                    path: path,
                    reason: "Invalid spring bounce",
                ) }
        }
        guard duration.isFinite,
              (0 ... 60).contains(duration)
        else { throw WhereThemeValidationError(
            path: path,
            reason: "Invalid animation duration",
        ) }
    }

    static func validate(_: ViewFontDescriptor.Weight, path _: String) throws {}
    static func validate(_: ViewFontDescriptor.Design, path _: String) throws {}
    static func validate(_: WhereThemeBlend, path _: String) throws {}
    static func validate(_: WhereThemeTextAlignment, path _: String) throws {}
    // Surface resolvers validate their constituent fields before creating native values.
    static func validate(_: WhereThemeSurface, path _: String) throws {}
    static func validate(_: WhereThemeMatteSurface, path _: String) throws {}
    static func validate(_: WhereThemeTintAdjustment, path _: String) throws {}
}
