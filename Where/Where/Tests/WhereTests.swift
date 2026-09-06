import Inspector
@_spi(Testing) import PeriscopeCore
import SwiftUI
import Testing
import UIKit
@testable import Where
import WhereCore
import WhereCrashReporting
import WhereUI

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

    @Test func delegateStartsEveryReportingControllerBeforeItsRuntime() {
        var events: [String] = []
        let runtime = RuntimeSpy()
        runtime.onLaunch = { events.append("runtime") }
        let delegate = AppDelegate(
            runtime: runtime,
            reportingControllers: [
                ReportingControllerSpy { events.append("first-reporter") },
                ReportingControllerSpy { events.append("second-reporter") },
            ],
        )

        _ = delegate.application(
            UIApplication.shared,
            didFinishLaunchingWithOptions: nil,
        )

        #expect(events == ["first-reporter", "second-reporter", "runtime"])
    }

    #if DEBUG
        @Test func ordinaryDebugBuildUsesLocalOnlyStorageAcrossRelaunches() {
            #expect(
                RegularApplicationRuntime.storeStorage(forCloudKitValidationBuild: false)
                    == .localOnly,
            )
        }

        @Test func cloudKitValidationBuildUsesCloudKitStorageAcrossRelaunches() {
            #expect(
                RegularApplicationRuntime.storeStorage(forCloudKitValidationBuild: true)
                    == .cloudKit,
            )
        }

        @Test func regularRuntimeUsesTheProcessReportingPreferencesForItsModel() {
            let preferences = WherePreferences(store: InMemoryKeyValueStore())
            let effective = DiagnosticReportingConfiguration.defaults(isDebugBuild: true)
            let runtime = RegularApplicationRuntime(
                preferences: preferences,
                effectiveDiagnosticReportingConfiguration: effective,
                applyRemoteLogging: { _, _ in },
            )

            preferences.hasOnboarded = true
            runtime.model.diagnosticReporting.sharesCrashReports = false
            runtime.model.diagnosticReporting.sharesSessionReplays = true

            #expect(runtime.model.hasOnboarded)
            #expect(preferences.diagnosticReportingConfiguration.sharesCrashReports == false)
            #expect(preferences.diagnosticReportingConfiguration.sharesSessionReplays)
        }

        @Test func selectingInspectorConstructsOnlyInspectorRuntime() throws {
            let fixture = try ModeFixture()
            defer { fixture.cleanup() }
            fixture.controller.scheduleInspector()
            var regularCount = 0
            var inspectorCount = 0

            let selected = AppDelegate.selectRuntime(
                modeController: fixture.controller,
                fileManager: .default,
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
                fileManager: .default,
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

        @Test func constructingRegularRuntimeConsumesDemoRequestOnce() throws {
            let fixture = try ModeFixture()
            defer { fixture.cleanup() }
            fixture.controller.scheduleDemo(.allIssues)

            _ = RegularApplicationRuntime(
                preferences: WherePreferences(store: InMemoryKeyValueStore()),
                effectiveDiagnosticReportingConfiguration: .defaults(isDebugBuild: true),
                applyRemoteLogging: { _, _ in },
                developerLaunchController: fixture.controller,
            )

            #expect(fixture.controller.nextLaunch == .regularApplication)
            #expect(fixture.controller.consumeDemoConfiguration() == nil)
        }

        @Test func pendingStoreRecoveryCompletesBeforeRuntimeConstruction() async throws {
            let fixture = try ModeFixture()
            defer { fixture.cleanup() }
            let rootURL = FileManager.default.temporaryDirectory.appending(
                path: "where-boot-recovery-\(UUID().uuidString)",
                directoryHint: .isDirectory,
            )
            try FileManager.default.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true,
            )
            defer { try? FileManager.default.removeItem(at: rootURL) }
            let storeURL = rootURL.appending(path: "Periscope.store")
            let recoveryStorageURL = rootURL.appending(
                path: "Periscope-Journals",
                directoryHint: .isDirectory,
            )
            try Data("late store write".utf8).write(to: storeURL)
            try FileManager.default.createDirectory(
                at: recoveryStorageURL,
                withIntermediateDirectories: true,
            )
            try Data("stale journal".utf8).write(
                to: recoveryStorageURL.appending(path: "segment"),
            )
            try fixture.controller.inspectorModeController.scheduleStoreFamilyErasure(
                storeURL: storeURL,
                storageRootURL: rootURL,
                recoveryStorageURLs: [recoveryStorageURL],
            )
            var regularFactorySawRecoveryArtifacts = true

            _ = AppDelegate.selectRuntime(
                modeController: fixture.controller,
                fileManager: .default,
                regular: {
                    regularFactorySawRecoveryArtifacts = [
                        storeURL,
                        recoveryStorageURL,
                    ].contains {
                        FileManager.default.fileExists(
                            atPath: $0.path(percentEncoded: false),
                        )
                    }
                    return RuntimeSpy()
                },
                inspector: {
                    RuntimeSpy()
                },
            )

            #expect(regularFactorySawRecoveryArtifacts == false)

            // The exact Periscope schema and session bootstrap can create a
            // fresh store after boot recovery; this is the path whose failure
            // hides logging tools in the regular developer menu.
            let store = try await PeriscopeStore.onDisk(
                databaseURL: storeURL,
                session: .current(attributes: [:]),
            )
            #expect(try await store.sessions().count == 1)
        }

        @Test func failedPendingRecoveryConstructsOnlyInspectorRuntime() throws {
            let fixture = try ModeFixture()
            defer { fixture.cleanup() }
            let storageRootURL = FileManager.default.temporaryDirectory.appending(
                path: "where-boot-root-\(UUID().uuidString)",
                directoryHint: .isDirectory,
            )
            let outsideRootURL = FileManager.default.temporaryDirectory.appending(
                path: "where-boot-outside-\(UUID().uuidString)",
                directoryHint: .isDirectory,
            )
            try FileManager.default.createDirectory(
                at: storageRootURL,
                withIntermediateDirectories: true,
            )
            try FileManager.default.createDirectory(
                at: outsideRootURL,
                withIntermediateDirectories: true,
            )
            defer { try? FileManager.default.removeItem(at: storageRootURL) }
            defer { try? FileManager.default.removeItem(at: outsideRootURL) }
            let storeURL = outsideRootURL.appending(path: "Periscope.store")
            try Data("store".utf8).write(to: storeURL)
            try fixture.controller.inspectorModeController.scheduleStoreFamilyErasure(
                storeURL: storeURL,
                storageRootURL: storageRootURL,
                recoveryStorageURLs: [],
            )
            var regularCount = 0
            var inspectorCount = 0

            _ = AppDelegate.selectRuntime(
                modeController: fixture.controller,
                fileManager: .default,
                regular: {
                    regularCount += 1
                    return RuntimeSpy()
                },
                inspector: {
                    inspectorCount += 1
                    return RuntimeSpy()
                },
            )

            #expect(regularCount == 0)
            #expect(inspectorCount == 1)
            #expect(fixture.controller.nextLaunch == .inspector)
            #expect(fixture.controller.inspectorModeController.pendingStoreErasureError != nil)
        }

        @Test func inspectorConfigurationNamesAppInspectionResources() throws {
            let suiteName = "where.inspector.configuration.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let groupURL = FileManager.default.temporaryDirectory
                .appending(path: "where-inspector-group", directoryHint: .isDirectory)
            let whereStoreURL = groupURL.appending(path: "default.store")
            let periscopeStorageRootURL = groupURL
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
            let periscopeStoreURL = periscopeStorageRootURL
                .appending(path: "Periscope.store")
            let periscopeRecoveryStorageURL = periscopeStoreURL
                .deletingLastPathComponent()
                .appending(path: "Periscope-Journals", directoryHint: .isDirectory)

            let configuration = WhereInspectorApplicationRuntime.makeConfiguration(
                fileManager: .default,
                userDefaults: defaults,
                bundleIdentifier: suiteName,
                groupURL: groupURL,
                whereStoreURL: whereStoreURL,
                periscopeStoreURL: periscopeStoreURL,
                periscopeRecoveryStorageURLs: [periscopeRecoveryStorageURL],
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
                configuration.swiftDataSources.compactMap(\.storeURL)
                    == [whereStoreURL, periscopeStoreURL],
            )
            #expect(
                configuration.swiftDataSources.map(\.storageRootURL)
                    == [groupURL, periscopeStorageRootURL],
            )
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
            #expect(
                configuration.swiftDataSources[1].recoveryStorageURLs
                    == [periscopeRecoveryStorageURL],
            )
        }
    #endif
}

@MainActor
private final class RuntimeSpy: WhereApplicationRuntime {
    private(set) var launchCount = 0
    private(set) var rootCount = 0
    var onLaunch: () -> Void = {}

    func didFinishLaunching(
        application _: UIApplication,
        options _: [UIApplication.LaunchOptionsKey: Any]?,
    ) -> Bool {
        launchCount += 1
        onLaunch()
        return true
    }

    func makeRootView() -> AnyView {
        rootCount += 1
        return AnyView(EmptyView())
    }
}

@MainActor
private struct ReportingControllerSpy: WhereReportingController {
    let onStart: () -> Void

    func start() {
        onStart()
    }
}

#if DEBUG
    @MainActor
    private struct ModeFixture {
        let suiteName: String
        let defaults: UserDefaults
        let controller: WhereDeveloperLaunchController

        init() throws {
            suiteName = "where.app-runtime.\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suiteName))
            controller = WhereDeveloperLaunchController(
                userDefaults: defaults,
                inspectorModeController: InspectorModeController(userDefaults: defaults),
            )
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
#endif
