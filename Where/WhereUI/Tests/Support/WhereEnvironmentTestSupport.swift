import Inspector
import InstallerKit
@_spi(Testing) import InstallerKitUI
import PeriscopeCore
import PeriscopeTools
import SwiftUI
import Testing
import WhereCore
@testable import WhereUI

@MainActor
final class WhereEnvironmentTestSupport {
    let model: WhereModel
    let updates = InstallerPreview.model(.available)
    let inspector: PeriscopeInspector
    let launchController: WhereDeveloperLaunchController
    let cardDesigner = CardDesignerModel(configuration: .standard)
    private let defaults: UserDefaults
    private let suite: String

    init() async throws {
        model = Self.makeModel()
        inspector = try await PeriscopeInspector(
            system: .isolated(),
            store: PreviewSupport.previewLogStore(),
        )
        suite = "where.environment-tests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        launchController = WhereDeveloperLaunchController(
            userDefaults: defaults,
            inspectorModeController: InspectorModeController(userDefaults: defaults),
        )
        cardDesigner.appliesToApp = true
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
    }

    var environment: WhereEnvironment {
        .app(.init(
            model: model,
            updates: updates,
            developer: .init(
                inspector: inspector,
                launchController: launchController,
                cardDesigner: cardDesigner,
            ),
        ))
    }

    static func makeModel() -> WhereModel {
        WhereModel(
            services: PreviewSupport.previewServices(),
            preferences: PreviewSupport.previewPreferences(),
            logSystem: .isolated(),
            now: { PreviewSupport.referenceNow },
        )
    }

    final class Reads {
        var latest: Values?
    }

    struct Values: Equatable {
        let model: ObjectIdentifier?
        let session: ObjectIdentifier?
        let updates: ObjectIdentifier?
        let isInDemoMode: Bool
        let theme: WhereTheme
        let regionStyles: RegionStyleResolver
        let cache: ObjectIdentifier?
        let inspector: ObjectIdentifier?
        let launchController: ObjectIdentifier?
        let cardDesigner: ObjectIdentifier?
        let cardConfiguration: CardDesignerConfiguration?
    }

    struct Probe: View {
        let reads: Reads
        @Environment(WhereModel.self) private var model: WhereModel?
        @Environment(WhereSession.self) private var session: WhereSession?
        @Environment(UpdateModel.self) private var updates: UpdateModel?
        @Environment(WhereDeveloperLaunchController.self) private var launchController:
            WhereDeveloperLaunchController?
        @Environment(\.isInDemoMode) private var isInDemoMode
        @Environment(\.stylesheet) private var stylesheet
        @Environment(\.regionStyles) private var regionStyles
        @Environment(\.regionOutlinePathCache) private var cache
        @Environment(\.periscopeInspector) private var inspector
        @Environment(\.cardDesignerModel) private var cardDesigner
        @Environment(\.cardDesignerConfiguration) private var cardConfiguration

        var body: some View {
            Color.clear.onChange(of: values, initial: true) { _, values in
                reads.latest = values
            }
        }

        private var values: Values {
            Values(
                model: model.map(ObjectIdentifier.init),
                session: session.map(ObjectIdentifier.init),
                updates: updates.map(ObjectIdentifier.init),
                isInDemoMode: isInDemoMode,
                theme: stylesheet.theme,
                regionStyles: regionStyles,
                cache: cache.map(ObjectIdentifier.init),
                inspector: inspector.map(ObjectIdentifier.init),
                launchController: launchController.map(ObjectIdentifier.init),
                cardDesigner: cardDesigner.map(ObjectIdentifier.init),
                cardConfiguration: cardConfiguration,
            )
        }
    }
}
