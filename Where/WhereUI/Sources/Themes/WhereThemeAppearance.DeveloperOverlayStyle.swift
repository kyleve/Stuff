import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public struct DeveloperOverlayStyle: Codable, Hashable, Sendable {
        @CopyOnWrite public var launcher: WhereThemeAppearance.DeveloperOverlayStyle.Launcher? = nil
        public var edgeInset: BThemeValue<Double>?
        public var presentationAnimation: BThemeValue<WhereThemeAnimation>?
        @CopyOnWrite public var floatingWindow: WhereThemeAppearance.DeveloperOverlayStyle
            .FloatingWindow? = nil
        @CopyOnWrite public var panel: WhereThemeAppearance.DeveloperOverlayStyle.Panel? = nil
        @CopyOnWrite public var menu: WhereThemeAppearance.DeveloperOverlayStyle.Menu? = nil

        public init() {}

        func apply(
            to value: inout WhereStylesheet.DeveloperOverlayStyle,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            try launcher?.apply(
                to: &value.launcher,
                traits: traits,
                appearance: appearance,
                path: path + ".launcher",
            )
            if let authored = edgeInset {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".edgeInset")
                value.edgeInset = CGFloat(resolved)
            }
            if let authored = presentationAnimation {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".presentationAnimation")
                value.presentationAnimation = resolved.animation
            }
            try floatingWindow?.apply(
                to: &value.floatingWindow,
                traits: traits,
                appearance: appearance,
                path: path + ".floatingWindow",
            )
            try panel?.apply(
                to: &value.panel,
                traits: traits,
                appearance: appearance,
                path: path + ".panel",
            )
            try menu?.apply(
                to: &value.menu,
                traits: traits,
                appearance: appearance,
                path: path + ".menu",
            )
        }
    }
}

extension WhereThemeAppearance.DeveloperOverlayStyle {
    public struct FloatingWindow: Codable, Hashable, Sendable {
        public var maxWidth: BThemeValue<Double>?
        public var maxHeight: BThemeValue<Double>?
        public var heightFraction: BThemeValue<Double>?
        public var minSize: BThemeValue<WhereThemeSize>?
        public var maxContentInsetFraction: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.DeveloperOverlayStyle.FloatingWindow,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = maxWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".maxWidth")
                value.maxWidth = CGFloat(resolved)
            }
            if let authored = maxHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".maxHeight")
                value.maxHeight = CGFloat(resolved)
            }
            if let authored = heightFraction {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".heightFraction")
                value.heightFraction = CGFloat(resolved)
            }
            if let authored = minSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".minSize")
                value.minSize = resolved.size
            }
            if let authored = maxContentInsetFraction {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".maxContentInsetFraction")
                value.maxContentInsetFraction = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.DeveloperOverlayStyle {
    public struct Launcher: Codable, Hashable, Sendable {
        public var diameter: BThemeValue<Double>?
        public var glyphRatio: BThemeValue<Double>?
        public var shadowColor: BThemeValue<ViewColorDescriptor>?
        public var shadowRadius: BThemeValue<Double>?
        public var shadowOffsetY: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.DeveloperOverlayStyle.Launcher,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = diameter {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".diameter")
                value.diameter = CGFloat(resolved)
            }
            if let authored = glyphRatio {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".glyphRatio")
                value.glyphRatio = CGFloat(resolved)
            }
            if let authored = shadowColor {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".shadowColor")
                value.shadowColor = appearance.color(resolved)
            }
            if let authored = shadowRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".shadowRadius")
                value.shadowRadius = CGFloat(resolved)
            }
            if let authored = shadowOffsetY {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".shadowOffsetY")
                value.shadowOffsetY = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.DeveloperOverlayStyle {
    public struct Menu: Codable, Hashable, Sendable {
        public var maxWidth: BThemeValue<Double>?
        public var launcherSpacing: BThemeValue<Double>?
        public var rowSpacing: BThemeValue<Double>?
        public var horizontalPadding: BThemeValue<Double>?
        public var verticalPadding: BThemeValue<Double>?
        public var minRowHeight: BThemeValue<Double>?
        public var cornerRadius: BThemeValue<Double>?
        public var subtitleSpacing: BThemeValue<Double>?
        public var iconWidth: BThemeValue<Double>?
        @CopyOnWrite public var motion: WhereThemeAppearance.DeveloperOverlayStyle.MenuMotion? = nil

        public init() {}

        func apply(
            to value: inout WhereStylesheet.DeveloperOverlayStyle.Menu,
            traits: BTraits,
            appearance: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = maxWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".maxWidth")
                value.maxWidth = CGFloat(resolved)
            }
            if let authored = launcherSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".launcherSpacing")
                value.launcherSpacing = CGFloat(resolved)
            }
            if let authored = rowSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".rowSpacing")
                value.rowSpacing = CGFloat(resolved)
            }
            if let authored = horizontalPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".horizontalPadding")
                value.horizontalPadding = CGFloat(resolved)
            }
            if let authored = verticalPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".verticalPadding")
                value.verticalPadding = CGFloat(resolved)
            }
            if let authored = minRowHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".minRowHeight")
                value.minRowHeight = CGFloat(resolved)
            }
            if let authored = cornerRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".cornerRadius")
                value.cornerRadius = CGFloat(resolved)
            }
            if let authored = subtitleSpacing {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".subtitleSpacing")
                value.subtitleSpacing = CGFloat(resolved)
            }
            if let authored = iconWidth {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".iconWidth")
                value.iconWidth = CGFloat(resolved)
            }
            try motion?.apply(
                to: &value.motion,
                traits: traits,
                appearance: appearance,
                path: path + ".motion",
            )
        }
    }
}

extension WhereThemeAppearance.DeveloperOverlayStyle {
    public struct MenuMotion: Codable, Hashable, Sendable {
        public var animation: BThemeValue<WhereThemeAnimation>?
        public var stagger: BThemeValue<Double>?
        public var scale: BThemeValue<Double>?
        public var usesSpatialMotion: BThemeValue<Bool>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.DeveloperOverlayStyle.MenuMotion,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = animation {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".animation")
                value.animation = resolved.animation
            }
            if let authored = stagger {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    range: 0 ... 60,
                    path: path + ".stagger",
                )
                value.stagger = resolved
            }
            if let authored = scale {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".scale")
                value.scale = CGFloat(resolved)
            }
            if let authored = usesSpatialMotion {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".usesSpatialMotion")
                value.usesSpatialMotion = resolved
            }
        }
    }
}

extension WhereThemeAppearance.DeveloperOverlayStyle {
    public struct Panel: Codable, Hashable, Sendable {
        public var cornerRadius: BThemeValue<Double>?
        public var fullScreenInset: BThemeValue<Double>?
        public var shadowOpacity: BThemeValue<Double>?
        public var shadowRadius: BThemeValue<Double>?
        public var shadowOffsetY: BThemeValue<Double>?
        public var controlHorizontalPadding: BThemeValue<Double>?
        public var controlVerticalPadding: BThemeValue<Double>?
        public var dragHandleSize: BThemeValue<WhereThemeSize>?
        public var dragHandleMinHeight: BThemeValue<Double>?
        public var resizeGripSize: BThemeValue<Double>?
        public var resizeIconSize: BThemeValue<Double>?
        public var resizeGripClearance: BThemeValue<Double>?

        public init() {}

        func apply(
            to value: inout WhereStylesheet.DeveloperOverlayStyle.Panel,
            traits: BTraits,
            appearance _: ViewDocumentAppearance,
            path: String,
        ) throws {
            if let authored = cornerRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".cornerRadius")
                value.cornerRadius = CGFloat(resolved)
            }
            if let authored = fullScreenInset {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".fullScreenInset")
                value.fullScreenInset = CGFloat(resolved)
            }
            if let authored = shadowOpacity {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".shadowOpacity")
                value.shadowOpacity = resolved
            }
            if let authored = shadowRadius {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".shadowRadius")
                value.shadowRadius = CGFloat(resolved)
            }
            if let authored = shadowOffsetY {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".shadowOffsetY")
                value.shadowOffsetY = CGFloat(resolved)
            }
            if let authored = controlHorizontalPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(
                    resolved,
                    path: path + ".controlHorizontalPadding",
                )
                value.controlHorizontalPadding = CGFloat(resolved)
            }
            if let authored = controlVerticalPadding {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".controlVerticalPadding")
                value.controlVerticalPadding = CGFloat(resolved)
            }
            if let authored = dragHandleSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".dragHandleSize")
                value.dragHandleSize = resolved.size
            }
            if let authored = dragHandleMinHeight {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".dragHandleMinHeight")
                value.dragHandleMinHeight = CGFloat(resolved)
            }
            if let authored = resizeGripSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".resizeGripSize")
                value.resizeGripSize = CGFloat(resolved)
            }
            if let authored = resizeIconSize {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".resizeIconSize")
                value.resizeIconSize = CGFloat(resolved)
            }
            if let authored = resizeGripClearance {
                let resolved = authored.resolve(mode: traits.mode)
                try WhereThemeValidation.validate(resolved, path: path + ".resizeGripClearance")
                value.resizeGripClearance = CGFloat(resolved)
            }
        }
    }
}

extension WhereThemeAppearance.DeveloperOverlayStyle: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.launcher = inheritPatch(launcher, from: parent.launcher)
        result.edgeInset = edgeInset ?? parent.edgeInset
        result.presentationAnimation = presentationAnimation ?? parent.presentationAnimation
        result.floatingWindow = inheritPatch(floatingWindow, from: parent.floatingWindow)
        result.panel = inheritPatch(panel, from: parent.panel)
        result.menu = inheritPatch(menu, from: parent.menu)
        return result
    }
}

extension WhereThemeAppearance.DeveloperOverlayStyle.FloatingWindow: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.maxWidth = maxWidth ?? parent.maxWidth
        result.maxHeight = maxHeight ?? parent.maxHeight
        result.heightFraction = heightFraction ?? parent.heightFraction
        result.minSize = minSize ?? parent.minSize
        result.maxContentInsetFraction = maxContentInsetFraction ?? parent.maxContentInsetFraction
        return result
    }
}

extension WhereThemeAppearance.DeveloperOverlayStyle.Launcher: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.diameter = diameter ?? parent.diameter
        result.glyphRatio = glyphRatio ?? parent.glyphRatio
        result.shadowColor = shadowColor ?? parent.shadowColor
        result.shadowRadius = shadowRadius ?? parent.shadowRadius
        result.shadowOffsetY = shadowOffsetY ?? parent.shadowOffsetY
        return result
    }
}

extension WhereThemeAppearance.DeveloperOverlayStyle.Menu: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.maxWidth = maxWidth ?? parent.maxWidth
        result.launcherSpacing = launcherSpacing ?? parent.launcherSpacing
        result.rowSpacing = rowSpacing ?? parent.rowSpacing
        result.horizontalPadding = horizontalPadding ?? parent.horizontalPadding
        result.verticalPadding = verticalPadding ?? parent.verticalPadding
        result.minRowHeight = minRowHeight ?? parent.minRowHeight
        result.cornerRadius = cornerRadius ?? parent.cornerRadius
        result.subtitleSpacing = subtitleSpacing ?? parent.subtitleSpacing
        result.iconWidth = iconWidth ?? parent.iconWidth
        result.motion = inheritPatch(motion, from: parent.motion)
        return result
    }
}

extension WhereThemeAppearance.DeveloperOverlayStyle.MenuMotion: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.animation = animation ?? parent.animation
        result.stagger = stagger ?? parent.stagger
        result.scale = scale ?? parent.scale
        result.usesSpatialMotion = usesSpatialMotion ?? parent.usesSpatialMotion
        return result
    }
}

extension WhereThemeAppearance.DeveloperOverlayStyle.Panel: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.cornerRadius = cornerRadius ?? parent.cornerRadius
        result.fullScreenInset = fullScreenInset ?? parent.fullScreenInset
        result.shadowOpacity = shadowOpacity ?? parent.shadowOpacity
        result.shadowRadius = shadowRadius ?? parent.shadowRadius
        result.shadowOffsetY = shadowOffsetY ?? parent.shadowOffsetY
        result.controlHorizontalPadding = controlHorizontalPadding ?? parent
            .controlHorizontalPadding
        result.controlVerticalPadding = controlVerticalPadding ?? parent.controlVerticalPadding
        result.dragHandleSize = dragHandleSize ?? parent.dragHandleSize
        result.dragHandleMinHeight = dragHandleMinHeight ?? parent.dragHandleMinHeight
        result.resizeGripSize = resizeGripSize ?? parent.resizeGripSize
        result.resizeIconSize = resizeIconSize ?? parent.resizeIconSize
        result.resizeGripClearance = resizeGripClearance ?? parent.resizeGripClearance
        return result
    }
}
