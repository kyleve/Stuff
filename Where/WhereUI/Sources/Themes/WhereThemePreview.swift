#if DEBUG
    import BroadwayUI
    import SnapshotKit
    import SwiftUI
    import WhereCore

    /// Uses production cards, background, root injection, and surface composition.
    struct WhereThemePreview: View {
        let theme: PreparedWhereThemeDocument
        var body: some View {
            content.whereBroadwayRoot(themeDocument: theme)
        }

        private var content: some View {
            VStack(spacing: 94) {
                RegionSummaryCard(regionDays: .init(region: .california, days: 148), year: 2026)
                RegionSummaryCard(
                    regionDays: .init(region: .europeanUnion, days: 22),
                    variant: .compact,
                    year: 2026,
                )
            }
            .padding(24)
            .padding(.bottom, 38)
            .background { WhereThemePreviewBackground() }
        }

        @MainActor
        static func example(_ example: WhereThemeExamples) -> Self {
            do { return try Self(theme: example.prepare()) }
            catch { preconditionFailure("Invalid bundled theme: \(error)") }
        }
    }

    extension WhereThemePreview {
        enum AccessibilityPolicy: String, CaseIterable {
            case reduceMotion = "ReduceMotion"
            case reduceTransparency = "ReduceTransparency"
        }

        static func snapshot(_ policy: AccessibilityPolicy) throws -> SnapshotCase {
            let theme = try WhereThemeExamples.halloween.prepare()
            return SnapshotCase(
                name: policy.rawValue,
                configurations: SnapshotConfiguration.combinations(
                    devices: [.init(name: "iPhone", size: .intrinsic(maxWidth: 402))],
                    colorSchemes: [.light, .dark],
                ),
                referenceGroup: .init(rawValue: "halloween"),
            ) {
                WhereThemePreview(theme: theme).content
                    .bTraitOverrides { traits, overrides in
                        var accessibility = traits.accessibility
                        switch policy {
                            case .reduceMotion: accessibility.isReduceMotionEnabled = true
                            case .reduceTransparency: accessibility
                            .isReduceTransparencyEnabled = true
                        }
                        overrides.accessibility = accessibility
                    }
                    .whereBroadwayRoot(themeDocument: theme)
            }
        }

        enum Subject: String, CaseIterable {
            case forecast = "Forecast"
            case welcome = "Welcome"
            case privacy = "Privacy"
            case timeline = "Timeline"
            case appearance = "Appearance"
            case planning = "Planning"
        }

        static func snapshot(_ subject: Subject) throws -> SnapshotCase {
            let theme = try WhereThemeExamples.halloween.prepare()
            let cache = RegionOutlinePathCache()
            let report = PreviewSupport.itineraryYearReportModel()
            let model = PreviewSupport.loadedModel()
            let session = PreviewSupport.loadedSession()
            let preview = try WhereThemePreviewModel.bundled()
            preview.select(.halloween)
            let configurations: [SnapshotConfiguration] = switch subject {
                case .forecast, .welcome, .privacy: .componentLightDark
                case .timeline, .appearance, .planning: .fullContentPhoneLightDark
            }
            return SnapshotCase(
                name: subject.rawValue,
                configurations: configurations,
                referenceGroup: .init(rawValue: "halloween"),
                onReadyToSnapshot: {
                    await PreviewSupport.loadCardArtwork(
                        for: [.california, .newYork],
                        cache: cache,
                    )
                },
            ) {
                Group {
                    switch subject {
                        case .forecast:
                            LocationForecastPanel(
                                forecasts: report.forecasts.leadingForecasts(report: report.report),
                                microprintRegions: report.ranking.primary.map(\.region),
                                homeRegion: report.forecasts.planning.homeRegion,
                                planningAction: {},
                            ).padding(24).background { WhereThemePreviewBackground() }
                        case .welcome:
                            RegionWelcomeCard(
                                presentation: .init(region: .newYork, greeting: .returnVisit),
                                dismissAction: {},
                                planStayAction: { _ in },
                            )
                            .padding(40).background { WhereThemePreviewBackground() }
                        case .privacy:
                            PrivacyPassportCard(
                                presentation: .init(configuration: .defaults(isDebugBuild: false)),
                                disclosureInteraction: .linkToSettings,
                            )
                            .padding(24).background { WhereThemePreviewBackground() }
                        case .timeline:
                            YearView(report: report, initialMode: .timeline)
                        case .appearance:
                            NavigationStack { AppearanceSettingsView(report: report) }
                        case .planning:
                            PlannedStaysView(report: report)
                    }
                }
                .environment(model).environment(session)
                .whereThemePreview(preview)
                .environment(\.regionOutlinePathCache, cache)
                .whereBroadwayRoot(themeDocument: theme)
            }
        }
    }

    private struct WhereThemePreviewBackground: View {
        @Environment(\.whereComponentStylesheet) private var components
        var body: some View {
            (components[.locations].background ?? Color(.systemBackground)).ignoresSafeArea()
        }
    }

    #Preview("Halloween") { WhereThemePreview.example(.halloween) }
#endif
