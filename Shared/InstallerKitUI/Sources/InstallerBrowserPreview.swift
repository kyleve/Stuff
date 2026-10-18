#if DEBUG
    import InstallerKit
    import SwiftUI

    /// Browser fixtures include an older PR build and retained history below the installed build.
    @MainActor
    enum InstallerBrowserPreview {
        enum Scenario: String, CaseIterable {
            case available = "Available"
            case offline = "Offline"
            case empty = "Empty"
            case retired = "Retired"
            case local = "Local"
        }

        enum BuildScenario: String, CaseIterable {
            case otherChannel = "OtherChannel"
            case older = "OlderBuild"
            case installed = "Installed"
            case unavailable = "Unavailable"
            case rewritten = "RewrittenHistory"
            case missingDetails = "MissingDetails"

            var selection: UpdateBuildBrowser.Selection {
                switch self {
                    case .otherChannel: InstallerBrowserPreview.selection(channel: "pr-417", run: 9)
                    case .older: InstallerBrowserPreview.selection(channel: "pr-380", run: 11)
                    case .installed: InstallerBrowserPreview.selection(channel: "pr-380", run: 12)
                    case .unavailable, .rewritten, .missingDetails:
                        InstallerBrowserPreview.selection(channel: "pr-380", run: 14)
                }
            }

            @MainActor var model: UpdateModel {
                switch self {
                    case .otherChannel, .older,
                         .installed: InstallerBrowserPreview.model(.available)
                    case .unavailable: InstallerBrowserPreview.model(.retired)
                    case .rewritten: InstallerPreview.model(.rewritten)
                    case .missingDetails: InstallerPreview.model(.missingDetails)
                }
            }
        }

        nonisolated static func selection(channel: String, run: UInt64) -> UpdateBuildBrowser
            .Selection
        {
            .init(
                channel: InstalledBuild.Channel(rawValue: channel)!,
                build: .init(run: run, attempt: 1),
            )
        }

        static func model(_ scenario: Scenario) -> UpdateModel {
            do {
                return try InstallerPreview.model(
                    catalog: catalog(scenario),
                    installed: scenario == .local ? InstallerPreview
                        .localBuild(status: "dirty") : InstallerPreview.distribution(),
                    isOffline: scenario == .offline,
                )
            } catch {
                preconditionFailure("Invalid build browser fixture: \(error)")
            }
        }

        static func catalog(_ scenario: Scenario) throws -> UpdateCatalog {
            let source = try InstallerPreview
                .catalog(scenario == .empty ? .unpublished : .available)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var root = try JSONSerialization
                .jsonObject(with: encoder.encode(source)) as! [String: Any]
            var apps = root["apps"] as! [[String: Any]]
            var channels = apps[0]["channels"] as! [[String: Any]]
            if scenario != .empty {
                var releases = channels[0]["releases"] as! [[String: Any]]
                let olderSHA = String(repeating: "4", count: 40)
                releases[2]["baseSHA"] = olderSHA
                var older = releases[2]
                older["id"] = ["run": 11, "attempt": 1]
                older["sha"] = olderSHA
                older.removeValue(forKey: "baseSHA")
                older["manifestURL"] = "https://updates.example.com/manifests/example/pr-380/11-1.plist"
                older["commits"] = []
                releases.append(older)
                channels[0]["releases"] = releases
                channels[0]["active"] = scenario != .retired

                var other = releases[0]
                let otherSHA = String(repeating: "5", count: 40)
                other["id"] = ["run": 9, "attempt": 1]
                other["sha"] = otherSHA
                other["manifestURL"] = "https://updates.example.com/manifests/example/pr-417/9-1.plist"
                other["commits"] = [["sha": otherSHA, "subject": "Explore a new timeline layout"]]
                channels.append(["name": "pr-417", "active": true, "releases": [other]])
            }
            apps[0]["channels"] = channels
            root["apps"] = apps
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(
                UpdateCatalog.self,
                from: JSONSerialization.data(withJSONObject: root),
            )
        }

        static func navigation(to route: UpdateBrowserView.Route, model: UpdateModel) -> some View {
            NavigationStack(path: .constant([route])) {
                UpdateChannelsView(model: model)
                    .updateBrowserDestinations(model: model, branding: InstallerPreview.branding)
            }
            .installerBroadwayRoot()
        }
    }
#endif
