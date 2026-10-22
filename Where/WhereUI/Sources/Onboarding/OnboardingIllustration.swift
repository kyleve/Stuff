import RegionKit
import SwiftUI
import WhereCore

/// Read-only product specimens. Sample history never creates a store or session.
struct OnboardingIllustration: View {
    let page: OnboardingPage.ID
    let privacy: DiagnosticReportingConfiguration
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(spacing: stylesheet.spacing.large) {
            switch page {
                case .welcome:
                    VStack(spacing: stylesheet.spacing.large) {
                        RegionSummaryCard(
                            regionDays: RegionDays(region: .california, days: 128),
                            variant: .compact,
                            year: 2026,
                            showsRecordedPoints: false,
                        )
                        RegionSummaryCard(
                            regionDays: RegionDays(region: .newYork, days: 64),
                            variant: .compact,
                            year: 2026,
                            showsRecordedPoints: false,
                        )
                    }
                    sampleLabel
                case .automatic:
                    YearRibbon(
                        days: OnboardingSampleHistory.days,
                        year: 2026,
                        calendar: OnboardingSampleHistory.calendar,
                    )
                    sampleLabel
                case .privacy:
                    PrivacyPassportCard(
                        presentation: PrivacyPassportPresentation(configuration: privacy),
                        disclosureInteraction: .staticContent,
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private var sampleLabel: some View {
        Text(.onboardingSampleHistory)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
    #Preview {
        OnboardingIllustration(page: .welcome, privacy: .defaults(isDebugBuild: false))
            .padding().whereBroadwayRoot()
    }
#endif
