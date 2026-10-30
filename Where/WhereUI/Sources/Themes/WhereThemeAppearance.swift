import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

public struct WhereThemeAppearance: Codable, Hashable, Sendable {
    public var spacing: WhereThemeAppearance.Spacing?
    public var size: WhereThemeAppearance.Size?
    public var card: WhereThemeAppearance.CardStyles?
    public var locationsBackground: WhereThemeAppearance.LocationsBackgroundStyle?
    public var locationCardStack: WhereThemeAppearance.LocationCardStackStyle?
    public var locationWelcome: WhereThemeAppearance.LocationWelcomeStyle?
    public var flightStatus: WhereThemeAppearance.FlightStatusStyle?
    public var flightReviewPoint: WhereThemeAppearance.FlightReviewPointStyle?
    public var calendar: WhereThemeAppearance.CalendarStyle?
    public var appIcon: WhereThemeAppearance.AppIconStyle?
    public var timeline: WhereThemeAppearance.TimelineStyle?
    public var regionMap: WhereThemeAppearance.RegionMapStyle?
    public var regionPicker: WhereThemeAppearance.RegionPickerStyle?
    public var evidence: WhereThemeAppearance.EvidenceStyle?
    public var locationForecast: WhereThemeAppearance.LocationForecastStyle?
    public var palette: WhereThemeAppearance.Palette?
    public var motion: WhereThemeAppearance.Motion?
    public var launch: WhereThemeAppearance.LaunchStyle?
    public var typography: WhereThemeAppearance.Typography?
    public var themePicker: WhereThemeAppearance.ThemePickerStyle?
    public var yearModePicker: WhereThemeAppearance.YearModePickerStyle?
    public var settings: WhereThemeAppearance.SettingsStyle?
    public var featureDiscovery: WhereThemeAppearance.FeatureDiscoveryStyle?
    public var passportSeal: WhereThemeAppearance.PassportSealStyle?
    public var privacyPassportCard: WhereThemeAppearance.PrivacyPassportCardStyle?
    public var openSourceStamp: WhereThemeAppearance.StampBannerStyle?
    public var plannedStayWarningStamp: WhereThemeAppearance.StampBannerStyle?
    public var developerOverlay: WhereThemeAppearance.DeveloperOverlayStyle?

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
