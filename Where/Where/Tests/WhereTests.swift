import Inspector
import PeriscopeCore
import SwiftUI
import Testing
import UIKit
@testable import Where
import WhereCore

@MainActor
struct WhereAppTests {
    @Test func delegateForwardsLaunchAndRootToItsRuntime() {
        let runtime = RuntimeSpy()
        let delegate = AppDelegate(runtime: runtime)

        #expect(
            delegate.application(
                UIApplication.shared,
                didFinishLaunchingWithOptions: nil,
            ),
        )
        _ = delegate.runtime.makeRootView()

        #expect(runtime.launchCount == 1)
        #expect(runtime.rootCount == 1)
    }

    #if DEBUG
        @Test func selectingInspectorConstructsOnlyInspectorRuntime() throws {
            let fixture = try ModeFixture()
            defer { fixture.cleanup() }
            fixture.controller.enterInspectorOnNextLaunch()
            var regularCount = 0
            var inspectorCount = 0

            let selected = AppDelegate.selectRuntime(
                modeController: fixture.controller,
                regular: {
                    regularCount += 1
                    return RuntimeSpy()
                },
                inspector: {
                    inspectorCount += 1
                    return RuntimeSpy()
                },
            )

            _ = selected.makeRootView()
            #expect(regularCount == 0)
            #expect(inspectorCount == 1)
        }

        @Test func selectingRegularApplicationConstructsOnlyRegularRuntime() throws {
            let fixture = try ModeFixture()
            defer { fixture.cleanup() }
            var regularCount = 0
            var inspectorCount = 0

            _ = AppDelegate.selectRuntime(
                modeController: fixture.controller,
                regular: {
                    regularCount += 1
                    return RuntimeSpy()
                },
                inspector: {
                    inspectorCount += 1
                    return RuntimeSpy()
                },
            )

            #expect(regularCount == 1)
            #expect(inspectorCount == 0)
        }

        @Test func inspectorConfigurationNamesAppInspectionResources() throws {
            let suiteName = "where.inspector.configuration.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let groupURL = FileManager.default.temporaryDirectory
                .appending(path: "where-inspector-group", directoryHint: .isDirectory)

            let configuration = WhereInspectorApplicationRuntime.makeConfiguration(
                fileManager: .default,
                userDefaults: defaults,
                bundleIdentifier: suiteName,
                groupURL: groupURL,
            )

            #expect(
                configuration.fileContainers.map(\.id.rawValue)
                    == [
                        "documents",
                        "application-support",
                        "caches",
                        "temporary",
                        "app-group",
                    ],
            )
            #expect(configuration.fileContainers.last?.rootURL == groupURL)
            #expect(configuration.defaultsDomains.map(\.persistentDomainName) == [suiteName])
            #expect(
                configuration.swiftDataSources.map(\.id.rawValue)
                    == ["where", "periscope"],
            )
            #expect(
                configuration.swiftDataSources[0].modelTypes?.count
                    == SwiftDataStore.inspectorModelTypes.count,
            )
            #expect(
                configuration.swiftDataSources[1].modelTypes?.count
                    == PeriscopeStore.inspectorModelTypes.count,
            )
        }
    #endif
}

@MainActor
private final class RuntimeSpy: WhereApplicationRuntime {
    private(set) var launchCount = 0
    private(set) var rootCount = 0

    func didFinishLaunching(
        application _: UIApplication,
        options _: [UIApplication.LaunchOptionsKey: Any]?,
    ) -> Bool {
        launchCount += 1
        return true
    }

    func makeRootView() -> AnyView {
        rootCount += 1
        return AnyView(EmptyView())
    }
}

#if DEBUG
    @MainActor
    private struct ModeFixture {
        let suiteName: String
        let defaults: UserDefaults
        let controller: InspectorModeController

        init() throws {
            suiteName = "where.app-runtime.\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suiteName))
            controller = InspectorModeController(userDefaults: defaults)
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
#endif
