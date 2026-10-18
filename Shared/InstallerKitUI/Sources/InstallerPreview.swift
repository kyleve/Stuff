import InstallerKit
#if DEBUG
    import Foundation
    import SwiftUI

    /// Public wire-format fixtures exercise the same decoder, cache, and model as a distributed
    /// build.
    @MainActor
    @_spi(Testing)
    public enum InstallerPreview {
        public enum Scenario: String, CaseIterable {
            case available = "Available"
            case current = "Current"
            case retired = "Retired"
            case rewritten = "RewrittenHistory"
            case unavailable = "MissingHistory"
            case offline = "Offline"
            case unpublished = "Unpublished"
            case missingDetails = "MissingDetails"
            case retiredWithoutMain = "RetiredWithoutMain"
            case local = "Local"
            case localDirty = "LocalDirty"
            case localUnknown = "LocalUnknown"
            case localOffline = "LocalOffline"

            public var isOffline: Bool {
                self == .offline || self == .localOffline
            }
        }

        public static var branding: AppUpdateBranding {
            AppUpdateBranding(name: "Example Dev", subtitle: "Your next idea, ready to explore.")
        }

        private final class MemoryPreferences: UpdatePreferencesStoring {
            var installerUpdates = UpdatePreferences(cached: nil)
        }

        public static let date = Date(timeIntervalSince1970: 1_800_000_000)
        public static let channel = InstalledBuild.Channel(rawValue: "pr-380")!

        public static func model(_ scenario: Scenario) -> UpdateModel {
            do {
                let installed: InstalledBuild = switch scenario {
                    case .local, .localOffline: localBuild(status: "clean")
                    case .localDirty: localBuild(status: "dirty")
                    case .localUnknown: localBuild(status: "unknown")
                    case .available, .current, .retired, .rewritten, .unavailable, .offline,
                         .unpublished, .missingDetails, .retiredWithoutMain: distribution()
                }
                let catalog = try catalog(scenario)
                return model(
                    catalog: catalog,
                    installed: installed,
                    isOffline: scenario.isOffline,
                )
            } catch {
                preconditionFailure("Invalid development update preview: \(error)")
            }
        }

        static func model(
            catalog: UpdateCatalog,
            installed: InstalledBuild,
            isOffline: Bool,
        ) -> UpdateModel {
            let preferences = MemoryPreferences()
            preferences.installerUpdates = UpdatePreferences(cached: .init(
                feedURL: installed.feedURL,
                checkedAt: date,
                catalog: catalog,
            ))
            return UpdateModel(service: UpdateService(
                installed: installed,
                preferences: preferences,
                client: Client(catalog: catalog, isOffline: isOffline),
                now: { date },
            ))
        }

        public static func distribution() -> InstalledBuild {
            guard let value = InstalledBuild(infoDictionary: stamp) else {
                preconditionFailure("Invalid development stamp fixture")
            }
            return value
        }

        public static func localBuild(status: String) -> InstalledBuild {
            var info = stamp
            info["InstallerChannel"] = "local"
            info["InstallerRun"] = "unknown"
            info["InstallerAttempt"] = "unknown"
            info["InstallerGitStatus"] = status
            guard let value = InstalledBuild(infoDictionary: info) else {
                preconditionFailure("Invalid local stamp fixture")
            }
            return value
        }

        private static var stamp: [String: String] {
            [
                "InstallerAppID": "example",
                "CFBundleIdentifier": "com.example.development",
                "InstallerRepositoryURL": "https://github.com/example/Apps",
                "InstallerGitStatus": "clean",
                "InstallerChannel": "pr-380",
                "InstallerRun": "12",
                "InstallerAttempt": "1",
                "InstallerGitSHA": String(
                    repeating: "1",
                    count: 40,
                ),
                "InstallerFeedURL": "https://updates.example.com/updates.json",
            ]
        }

        public static func catalog(_ scenario: Scenario) throws -> UpdateCatalog {
            let first = String(repeating: "1", count: 40)
            let second = String(repeating: "2", count: 40)
            let third = String(repeating: "3", count: 40)
            func release(_ run: Int, sha: String, base: String?, subject: String) -> [String: Any] {
                var value: [String: Any] = [
                    "id": ["run": run, "attempt": 1],
                    "sha": sha,
                    "publishedAt": "2027-01-15T08:00:00Z",
                    "manifestURL": "https://updates.example.com/manifests/example/pr-380/\(run)-1.plist",
                    "historyChanged": scenario == .rewritten && run == 14,
                    "commits": [["sha": sha, "subject": subject]],
                ]
                if scenario != .missingDetails {
                    value["buildDetails"] = [
                        "version": "0.9.2",
                        "minimumOSVersion": "27.0",
                        "sizeBytes": 48_300_000,
                    ]
                }
                if let base { value["baseSHA"] = base }
                return value
            }
            let releases = [
                release(
                    14,
                    sha: third,
                    base: second,
                    subject: "Show update notes and an install action in Settings",
                ),
                release(
                    13,
                    sha: second,
                    base: first,
                    subject: "Publish main and labeled pull request builds",
                ),
                release(12, sha: first, base: nil, subject: "Add remote development installs"),
            ]
            let selected: [[String: Any]] = switch scenario {
                case .current: [releases[2]]
                case .unavailable: [releases[0]]
                case .available, .retired, .rewritten, .offline, .unpublished, .missingDetails,
                     .retiredWithoutMain, .local, .localDirty, .localUnknown,
                     .localOffline: releases
            }
            var mainRelease = releases[0]
            mainRelease["manifestURL"] = "https://updates.example.com/manifests/example/main/14-1.plist"
            var app: [String: Any] = [
                "id": "example",
                "name": "Example Dev",
                "bundleIdentifier": "com.example.development",
                "channels": [
                    [
                        "name": "pr-380",
                        "active": scenario != .retired && scenario != .retiredWithoutMain,
                        "releases": selected,
                    ],
                    [
                        "name": "main",
                        "active": scenario != .retiredWithoutMain,
                        "releases": [mainRelease],
                    ],
                ],
            ]
            if scenario == .unpublished { app["channels"] = [] }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(
                UpdateCatalog.self,
                from: JSONSerialization.data(withJSONObject: ["schemaVersion": 3, "apps": [app]]),
            )
        }

        struct Client: UpdateFetching {
            let catalog: UpdateCatalog
            let isOffline: Bool
            func fetch(from _: URL) async throws -> UpdateCatalog {
                if isOffline { throw URLError(.notConnectedToInternet) }
                return catalog
            }
        }
    }
#endif
