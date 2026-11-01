import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

public struct WhereThemeAppearance: Codable, Hashable, Sendable {
    @CopyOnWrite public var spacing: WhereThemeAppearance.Spacing? = nil
    @CopyOnWrite public var size: WhereThemeAppearance.Size? = nil
    @CopyOnWrite public var card: WhereThemeAppearance.CardStyles? = nil
    @CopyOnWrite public var locationsBackground: WhereThemeAppearance
        .LocationsBackgroundStyle? = nil
    @CopyOnWrite public var locationCardStack: WhereThemeAppearance.LocationCardStackStyle? = nil
    @CopyOnWrite public var locationWelcome: WhereThemeAppearance.LocationWelcomeStyle? = nil
    @CopyOnWrite public var flightStatus: WhereThemeAppearance.FlightStatusStyle? = nil
    @CopyOnWrite public var flightReviewPoint: WhereThemeAppearance.FlightReviewPointStyle? = nil
    @CopyOnWrite public var calendar: WhereThemeAppearance.CalendarStyle? = nil
    @CopyOnWrite public var appIcon: WhereThemeAppearance.AppIconStyle? = nil
    @CopyOnWrite public var timeline: WhereThemeAppearance.TimelineStyle? = nil
    @CopyOnWrite public var regionMap: WhereThemeAppearance.RegionMapStyle? = nil
    @CopyOnWrite public var regionPicker: WhereThemeAppearance.RegionPickerStyle? = nil
    @CopyOnWrite public var evidence: WhereThemeAppearance.EvidenceStyle? = nil
    @CopyOnWrite public var locationForecast: WhereThemeAppearance.LocationForecastStyle? = nil
    @CopyOnWrite public var palette: WhereThemeAppearance.Palette? = nil
    @CopyOnWrite public var motion: WhereThemeAppearance.Motion? = nil
    @CopyOnWrite public var launch: WhereThemeAppearance.LaunchStyle? = nil
    @CopyOnWrite public var typography: WhereThemeAppearance.Typography? = nil
    @CopyOnWrite public var themePicker: WhereThemeAppearance.ThemePickerStyle? = nil
    @CopyOnWrite public var yearModePicker: WhereThemeAppearance.YearModePickerStyle? = nil
    @CopyOnWrite public var settings: WhereThemeAppearance.SettingsStyle? = nil
    @CopyOnWrite public var featureDiscovery: WhereThemeAppearance.FeatureDiscoveryStyle? = nil
    @CopyOnWrite public var passportSeal: WhereThemeAppearance.PassportSealStyle? = nil
    @CopyOnWrite public var privacyPassportCard: WhereThemeAppearance
        .PrivacyPassportCardStyle? = nil
    @CopyOnWrite public var openSourceStamp: WhereThemeAppearance.StampBannerStyle? = nil
    @CopyOnWrite public var plannedStayWarningStamp: WhereThemeAppearance.StampBannerStyle? = nil
    @CopyOnWrite public var developerOverlay: WhereThemeAppearance.DeveloperOverlayStyle? = nil

    public init() {}

    func apply(
        to value: inout WhereStylesheet,
        traits: BTraits,
        appearance: ViewDocumentAppearance,
        path: String,
    ) throws {
        try spacing?.apply(
            to: &value.spacing,
            traits: traits,
            appearance: appearance,
            path: path + ".spacing",
        )
        try size?.apply(
            to: &value.size,
            traits: traits,
            appearance: appearance,
            path: path + ".size",
        )
        try card?.apply(
            to: &value.card,
            traits: traits,
            appearance: appearance,
            path: path + ".card",
        )
        try locationsBackground?.apply(
            to: &value.locationsBackground,
            traits: traits,
            appearance: appearance,
            path: path + ".locationsBackground",
        )
        try locationCardStack?.apply(
            to: &value.locationCardStack,
            traits: traits,
            appearance: appearance,
            path: path + ".locationCardStack",
        )
        try locationWelcome?.apply(
            to: &value.locationWelcome,
            traits: traits,
            appearance: appearance,
            path: path + ".locationWelcome",
        )
        try flightStatus?.apply(
            to: &value.flightStatus,
            traits: traits,
            appearance: appearance,
            path: path + ".flightStatus",
        )
        try flightReviewPoint?.apply(
            to: &value.flightReviewPoint,
            traits: traits,
            appearance: appearance,
            path: path + ".flightReviewPoint",
        )
        try calendar?.apply(
            to: &value.calendar,
            traits: traits,
            appearance: appearance,
            path: path + ".calendar",
        )
        try appIcon?.apply(
            to: &value.appIcon,
            traits: traits,
            appearance: appearance,
            path: path + ".appIcon",
        )
        try timeline?.apply(
            to: &value.timeline,
            traits: traits,
            appearance: appearance,
            path: path + ".timeline",
        )
        try regionMap?.apply(
            to: &value.regionMap,
            traits: traits,
            appearance: appearance,
            path: path + ".regionMap",
        )
        try regionPicker?.apply(
            to: &value.regionPicker,
            traits: traits,
            appearance: appearance,
            path: path + ".regionPicker",
        )
        try evidence?.apply(
            to: &value.evidence,
            traits: traits,
            appearance: appearance,
            path: path + ".evidence",
        )
        try locationForecast?.apply(
            to: &value.locationForecast,
            traits: traits,
            appearance: appearance,
            path: path + ".locationForecast",
        )
        try palette?.apply(
            to: &value.palette,
            traits: traits,
            appearance: appearance,
            path: path + ".palette",
        )
        try motion?.apply(
            to: &value.motion,
            traits: traits,
            appearance: appearance,
            path: path + ".motion",
        )
        try launch?.apply(
            to: &value.launch,
            traits: traits,
            appearance: appearance,
            path: path + ".launch",
        )
        try typography?.apply(
            to: &value.typography,
            traits: traits,
            appearance: appearance,
            path: path + ".typography",
        )
        try themePicker?.apply(
            to: &value.themePicker,
            traits: traits,
            appearance: appearance,
            path: path + ".themePicker",
        )
        try yearModePicker?.apply(
            to: &value.yearModePicker,
            traits: traits,
            appearance: appearance,
            path: path + ".yearModePicker",
        )
        try settings?.apply(
            to: &value.settings,
            traits: traits,
            appearance: appearance,
            path: path + ".settings",
        )
        try featureDiscovery?.apply(
            to: &value.featureDiscovery,
            traits: traits,
            appearance: appearance,
            path: path + ".featureDiscovery",
        )
        try passportSeal?.apply(
            to: &value.passportSeal,
            traits: traits,
            appearance: appearance,
            path: path + ".passportSeal",
        )
        try privacyPassportCard?.apply(
            to: &value.privacyPassportCard,
            traits: traits,
            appearance: appearance,
            path: path + ".privacyPassportCard",
        )
        try openSourceStamp?.apply(
            to: &value.openSourceStamp,
            traits: traits,
            appearance: appearance,
            path: path + ".openSourceStamp",
        )
        try plannedStayWarningStamp?.apply(
            to: &value.plannedStayWarningStamp,
            traits: traits,
            appearance: appearance,
            path: path + ".plannedStayWarningStamp",
        )
        try developerOverlay?.apply(
            to: &value.developerOverlay,
            traits: traits,
            appearance: appearance,
            path: path + ".developerOverlay",
        )
    }
}

extension WhereThemeAppearance: WhereThemePatch {
    func inheriting(_ parent: Self?) -> Self {
        guard let parent else { return self }
        var result = self
        result.spacing = inheritPatch(spacing, from: parent.spacing)
        result.size = inheritPatch(size, from: parent.size)
        result.card = inheritPatch(card, from: parent.card)
        result.locationsBackground = inheritPatch(
            locationsBackground,
            from: parent.locationsBackground,
        )
        result.locationCardStack = inheritPatch(locationCardStack, from: parent.locationCardStack)
        result.locationWelcome = inheritPatch(locationWelcome, from: parent.locationWelcome)
        result.flightStatus = inheritPatch(flightStatus, from: parent.flightStatus)
        result.flightReviewPoint = inheritPatch(flightReviewPoint, from: parent.flightReviewPoint)
        result.calendar = inheritPatch(calendar, from: parent.calendar)
        result.appIcon = inheritPatch(appIcon, from: parent.appIcon)
        result.timeline = inheritPatch(timeline, from: parent.timeline)
        result.regionMap = inheritPatch(regionMap, from: parent.regionMap)
        result.regionPicker = inheritPatch(regionPicker, from: parent.regionPicker)
        result.evidence = inheritPatch(evidence, from: parent.evidence)
        result.locationForecast = inheritPatch(locationForecast, from: parent.locationForecast)
        result.palette = inheritPatch(palette, from: parent.palette)
        result.motion = inheritPatch(motion, from: parent.motion)
        result.launch = inheritPatch(launch, from: parent.launch)
        result.typography = inheritPatch(typography, from: parent.typography)
        result.themePicker = inheritPatch(themePicker, from: parent.themePicker)
        result.yearModePicker = inheritPatch(yearModePicker, from: parent.yearModePicker)
        result.settings = inheritPatch(settings, from: parent.settings)
        result.featureDiscovery = inheritPatch(featureDiscovery, from: parent.featureDiscovery)
        result.passportSeal = inheritPatch(passportSeal, from: parent.passportSeal)
        result.privacyPassportCard = inheritPatch(
            privacyPassportCard,
            from: parent.privacyPassportCard,
        )
        result.openSourceStamp = inheritPatch(openSourceStamp, from: parent.openSourceStamp)
        result.plannedStayWarningStamp = inheritPatch(
            plannedStayWarningStamp,
            from: parent.plannedStayWarningStamp,
        )
        result.developerOverlay = inheritPatch(developerOverlay, from: parent.developerOverlay)
        return result
    }
}
