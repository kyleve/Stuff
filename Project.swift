import ProjectDescription

let destinations: Destinations = [.iPhone, .iPad]
let deployment: DeploymentTargets = .iOS("27.1")

/// Local Swift package (see root `Package.swift`) for the library products
/// (WhereCore, WhereUI, TestHostSupport, the Broadway modules, …).
private let stuffPackage = Package.local(path: .relativeToRoot("."))
private let sfSafeSymbolsPackage = Package.remote(
    url: "https://github.com/SFSafeSymbols/SFSafeSymbols",
    requirement: .upToNextMajor(from: "7.0.0"),
)

/// Apple Developer Team used to code-sign when building to a device, read from
/// the `TUIST_DEVELOPMENT_TEAM` environment variable so each developer's team ID
/// stays out of the checked-in project. Set it in `.mise.local.toml` (gitignored)
/// and it's picked up automatically by `mise exec -- tuist generate` (i.e. `./ide`).
/// When unset — e.g. on CI or a fresh clone — no `DEVELOPMENT_TEAM` is written and
/// Xcode falls back to its defaults.
private let developmentTeam = Environment.developmentTeam.getString(default: "")

private struct WhereAudience {
    struct Installer {
        let appID: String
        let repositoryURL: String
        let feedURL: String
    }

    enum Variant {
        case debug
        case release
    }

    let schemeName: String
    let configurationName: ConfigurationName
    let variant: Variant
    let condition: String
    let value: String
    let displayName: String
    let appBundleID: String
    let widgetBundleID: String
    let shareBundleID: String
    let appGroupIdentifier: String
    let primaryAppIconName: String
    let installer: Installer?

    func configuration(settings: SettingsDictionary = [:]) -> Configuration {
        switch variant {
            case .debug: .debug(name: configurationName, settings: settings)
            case .release: .release(name: configurationName, settings: settings)
        }
    }
}

private let whereAudiences: [WhereAudience] = [
    WhereAudience(
        schemeName: "Where Development",
        configurationName: "Debug",
        variant: .debug,
        condition: "WHERE_DEVELOPMENT",
        value: "development",
        displayName: "Where Dev",
        appBundleID: "com.stuff.where.development",
        widgetBundleID: "com.stuff.where.development.widgets",
        shareBundleID: "com.stuff.where.development.share",
        appGroupIdentifier: "group.com.stuff.where.development",
        primaryAppIconName: "AppIcon",
        installer: .init(
            appID: "where",
            repositoryURL: "https://github.com/kyleve/Stuff",
            feedURL: "https://kyleve.github.io/Stuff/updates.json",
        ),
    ),
    WhereAudience(
        schemeName: "Where Beta",
        configurationName: "Beta",
        variant: .release,
        condition: "WHERE_BETA",
        value: "beta",
        displayName: "Where",
        appBundleID: "com.stuff.where",
        widgetBundleID: "com.stuff.where.widgets",
        shareBundleID: "com.stuff.where.share",
        appGroupIdentifier: "group.com.stuff.where",
        primaryAppIconName: "AppIcon",
        installer: nil,
    ),
    WhereAudience(
        schemeName: "Where App Store",
        configurationName: "Release",
        variant: .release,
        condition: "WHERE_APP_STORE",
        value: "appStore",
        displayName: "Where",
        appBundleID: "com.stuff.where",
        widgetBundleID: "com.stuff.where.widgets",
        shareBundleID: "com.stuff.where.share",
        appGroupIdentifier: "group.com.stuff.where",
        primaryAppIconName: "AppIcon",
        installer: nil,
    ),
]

private enum WhereHostTarget {
    case app
    case widget
    case share

    /// CI supplies the UUID of each installed ad hoc profile. Empty values
    /// retain Xcode's normal signing behavior for local development.
    var adhocProfile: String {
        switch self {
            case .app: Environment.whereAdhocAppProfile.getString(default: "")
            case .widget: Environment.whereAdhocWidgetProfile.getString(default: "")
            case .share: Environment.whereAdhocShareProfile.getString(default: "")
        }
    }

    func bundleID(for audience: WhereAudience) -> String {
        switch self {
            case .app: audience.appBundleID
            case .widget: audience.widgetBundleID
            case .share: audience.shareBundleID
        }
    }
}

private func whereHostSettings(
    _ target: WhereHostTarget,
    base: SettingsDictionary = [:],
) -> Settings {
    .settings(
        base: base,
        configurations: whereAudiences.map { audience in
            var settings: SettingsDictionary = [
                "PRODUCT_BUNDLE_IDENTIFIER": .string(target.bundleID(for: audience)),
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": .string(
                    "$(inherited) \(audience.condition)",
                ),
                "WHERE_APP_GROUP_IDENTIFIER": .string(audience.appGroupIdentifier),
                "WHERE_AUDIENCE": .string(audience.value),
                "WHERE_DISPLAY_NAME": .string(audience.displayName),
                "WHERE_PRIMARY_APP_ICON_NAME": .string(audience.primaryAppIconName),
            ]
            if case .app = target {
                settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = .string(audience
                    .primaryAppIconName)
                if let installer = audience.installer {
                    settings["INSTALLER_APP_ID"] = .string(installer.appID)
                    settings["INSTALLER_REPOSITORY_URL"] = .string(installer.repositoryURL)
                    settings["INSTALLER_FEED_URL"] = .string(installer.feedURL)
                    // CI's archive command overrides this with its published channel and run.
                    settings["INSTALLER_CHANNEL"] = "local"
                }
            }
            if case .debug = audience.variant, !target.adhocProfile.isEmpty {
                settings["CODE_SIGN_STYLE[sdk=iphoneos*]"] = "Manual"
                settings["CODE_SIGN_IDENTITY[sdk=iphoneos*]"] = "Apple Distribution"
                settings["PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]"] = .string(target
                    .adhocProfile)
            }
            return audience.configuration(settings: settings)
        },
    )
}

/// Base build settings applied to every Tuist-generated target.
///
/// `STRING_CATALOG_GENERATE_SYMBOLS` turns on Xcode's type-safe String Catalog
/// symbol generation for the app and app-extension targets (Where, WhereWidgets,
/// WhereShareExtension, …). The SwiftPM package targets declared in `Package.swift`
/// (WhereUI, WhereCore, RegionKit, LifecycleKitUI) get symbol generation
/// automatically from the toolchain, so this only needs to reach the
/// Tuist-native targets.
///
/// `DEVELOPMENT_TEAM` is threaded in from the environment when present (see above).
private let projectSettings: Settings = .settings(
    base: developmentTeam.isEmpty
        ? ["STRING_CATALOG_GENERATE_SYMBOLS": "YES"]
        : [
            "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
            "DEVELOPMENT_TEAM": .string(developmentTeam),
        ],
    configurations: whereAudiences.map { $0.configuration() },
    defaultConfiguration: "Debug",
)

/// App Group shared by the Where app, its widget extension, and its share
/// extension so every audience's processes see the same on-disk SwiftData
/// store and widget snapshot JSON. The host injects the matching build setting
/// into WhereCore; no package target owns a global App Group identifier.
let whereAppGroupEntitlements: Entitlements = .dictionary([
    "com.apple.security.application-groups": .array([
        .string("$(WHERE_APP_GROUP_IDENTIFIER)"),
    ]),
])

/// The app additionally owns the CloudKit container that mirrors its
/// SwiftData store. Extensions deliberately keep the App Group-only
/// entitlement above: they write the shared local store and let the app's
/// CloudKit-backed container publish those changes when it next opens.
let whereAppEntitlements: Entitlements = .dictionary([
    // Xcode replaces this development placeholder with the environment from
    // the selected provisioning profile. Keeping the entitlement in the
    // target is what makes automatic signing request Push Notifications.
    "aps-environment": .string("development"),
    "com.apple.security.application-groups": .array([
        .string("$(WHERE_APP_GROUP_IDENTIFIER)"),
    ]),
    "com.apple.developer.icloud-container-identifiers": .array([
        .string("iCloud.com.stuff.where"),
    ]),
    "com.apple.developer.icloud-services": .array([.string("CloudKit")]),
    "com.apple.developer.ubiquity-kvstore-identifier": .string(
        "$(TeamIdentifierPrefix)com.stuff.where",
    ),
])

/// The environment the LFS reference images were recorded on, and the single
/// source of truth for it.
///
/// The `assertSnapshots` runner compares the `SNAPSHOT_EXPECTED_*` values
/// against the live simulator and fails fast with one clear message on a
/// mismatched runtime, screen scale, or timezone — instead of hundreds of
/// confusing image diffs. `TZ` pins the test process's timezone itself: several
/// references bake Pacific wall-clock dates/times into the image (widget day
/// labels, log-viewer timestamps), so an unpinned UTC CI runner would shift
/// every date-rendering snapshot. `SNAPSHOT_EXPECTED_TIMEZONE` is the guard
/// that verifies the `TZ` pin actually reached the test process.
///
/// Set on **both** the snapshot targets and the aggregate scheme below, which
/// is deliberate: Tuist autogenerates a scheme per target, so a target that
/// carries these is correctly pinned when someone runs that one bundle from
/// Xcode, while the aggregate scheme covers the CI invocation. Setting them in
/// only one place leaves the other silently unpinned — and an unpinned run
/// doesn't fail loudly, it just compares against references recorded somewhere
/// else.
/// Points SwiftPM's generated `Bundle.module` accessors at the built-products
/// directory, where every package resource bundle lands — set on every test
/// target and test action, hosted or not.
///
/// `PACKAGE_RESOURCE_BUNDLE_PATH` is the accessors' own first candidate
/// (DEBUG-only, which test builds are; see any generated
/// `resource_bundle_accessor.swift`, rdar://107766372). It exists because the
/// default candidates — `Bundle.main` and `Bundle(for: BundleFinder.self)` —
/// assume the class and its resource bundle travel together, and Xcode 27
/// beta 4 broke that assumption for hosted tests: its package linking dedupes
/// a statically-absorbed product's code into the one image that carries it
/// (e.g. WhereCore's classes live only inside `WhereUI.framework`), while the
/// product's resource bundle is still copied into each `.xctest`. The class
/// resolves to the framework, the bundle sits unseen in the test bundle, and
/// the accessor's `fatalError` kills the host (CI run 30484782772).
///
/// The pre-#144 remedy — embedding WhereCore in `StuffTestHost` so
/// `Bundle.main` resolves — can't come back: under beta 4 a package product
/// consumed by both the host and the bundles loses its String Catalog
/// generate-symbols step and the build fails. The env override sidesteps
/// linking entirely; simulator processes read host paths, so the
/// built-products directory is always reachable. Remove this only when a
/// later Xcode makes the default candidates resolve for hosted tests again —
/// prove it by deleting the variable and running the full `Stuff-iOS-Tests`
/// scheme on the Xcode CI uses.
let packageResourceEnvironment: [String: EnvironmentVariable] = [
    "PACKAGE_RESOURCE_BUNDLE_PATH": "$(BUILT_PRODUCTS_DIR)",
]

let snapshotEnvironment: [String: EnvironmentVariable] =
    packageResourceEnvironment.merging([
