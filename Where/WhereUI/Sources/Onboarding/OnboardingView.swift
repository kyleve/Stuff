import LifecycleKit
import SwiftUI
import WhereCore

/// First-run onboarding, run as one interactive launch step. A short paged
/// intro to the passport concept, then picking the primary regions you spend
/// time in and giving each a look, then the background-location permission
/// request — the natural place to ask for Always, rather than burying it in
/// Settings.
///
/// When the user finishes it commits the picked regions + appearances to the
/// store (which becomes the tracked-region set), persists `hasOnboarded`, and
/// resolves the `LifecycleStepUIBridge` so the launch continues; the following
/// authorization-sync step then seeds region styling and picks up whatever
/// permission was granted.
public struct OnboardingView: View {
    // Onboarding straddles both: it persists the app-level `hasOnboarded` flag
    // (model) and kicks off background tracking + the region commit through the
    // session, which the `open-store` step has already built by the time this
    // step runs.
    @Environment(WhereModel.self) private var model
    @Environment(WhereSession.self) private var session
    @Environment(\.stylesheet) private var stylesheet
    private let bridge: LifecycleStepUIBridge

    /// The ordered onboarding phases. An explicit state machine (rather than
    /// loose flags) so only one screen is ever showing and the transitions are
    /// obvious.
    private enum Phase: Hashable {
        case intro
        case pickRegions
        case customize
        case location
    }

    @State private var phase: Phase = .intro
    @State private var page = 0
    @State private var selection = PrimaryRegionSelectionModel()
    @State private var isFinishing = false

    private static let logger = WhereLog.channel(.model)

    public init(bridge: LifecycleStepUIBridge) {
        self.bridge = bridge
    }

    private let pages = OnboardingPage.all

    public var body: some View {
        Group {
            switch phase {
                case .intro: intro
                case .pickRegions: pickRegions
                case .customize: customize
                case .location: location
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    stylesheet.palette.onboarding.backgroundTop,
                    stylesheet.palette.onboarding.backgroundBottom,
                ],
                startPoint: .top,
                endPoint: .bottom,
            )
            .ignoresSafeArea(),
        )
        .animation(stylesheet.motion.reducedReveal, value: phase)
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(spacing: stylesheet.spacing.xxxLarge) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index])
                        .tag(index)
                        .padding(.horizontal, stylesheet.spacing.xxxLarge)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            introFooter
                .padding(.horizontal, stylesheet.spacing.xxxLarge)
                .padding(.bottom, stylesheet.spacing.xxxLarge)
        }
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: stylesheet.spacing.xxxLarge) {
            Spacer(minLength: 0)
            Image(systemName: page.symbol)
                .font(stylesheet.typography.onboardingIcon)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(spacing: stylesheet.spacing.large) {
                Text(page.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
    }

    private var introFooter: some View {
        Button {
            if page < pages.count - 1 {
                withAnimation { page += 1 }
            } else {
                phase = .pickRegions
            }
        } label: {
            Text(Strings.onboardingContinue)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: - Pick regions

    private var pickRegions: some View {
        VStack(spacing: stylesheet.spacing.large) {
            VStack(spacing: stylesheet.spacing.small) {
                Text(Strings.onboardingRegionsTitle)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(Strings.regionPickerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, stylesheet.spacing.xxxLarge)
            .padding(.top, stylesheet.spacing.xxxLarge)

            RegionPickerView(model: selection)

            Button {
                phase = .customize
            } label: {
                Text(Strings.onboardingNext)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!selection.hasSelection)
            .padding(.horizontal, stylesheet.spacing.xxxLarge)
            .padding(.bottom, stylesheet.spacing.xxxLarge)
        }
    }

    // MARK: - Customize

    private var customize: some View {
        RegionCustomizeView(
            model: selection,
            onBack: { phase = .pickRegions },
            onFinish: { phase = .location },
        )
    }

    // MARK: - Location

    private var location: some View {
        VStack(spacing: stylesheet.spacing.xxxLarge) {
            Spacer(minLength: 0)
            Image(systemName: "location.fill.viewfinder")
                .font(stylesheet.typography.onboardingIcon)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(spacing: stylesheet.spacing.large) {
                Text(Strings.onboardingLocationTitle)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(Strings.onboardingLocationDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)

            VStack(spacing: stylesheet.spacing.large) {
                Button {
                    // Request Always-location right here so the system prompt
                    // maps 1:1 to the tap; the launch's tracking-reconcile step
                    // picks up whatever was granted.
                    finish(enableLocation: true)
                } label: {
                    Text(Strings.onboardingEnableLocation)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(Strings.onboardingNotNow) {
                    finish(enableLocation: false)
                }
                .controlSize(.large)
            }
            .disabled(isFinishing)
        }
        .padding(.horizontal, stylesheet.spacing.xxxLarge)
        .padding(.bottom, stylesheet.spacing.xxxLarge)
    }

    /// Commit the picked regions + appearances, optionally request location,
    /// then persist `hasOnboarded` and resolve the step so the launch continues.
    private func finish(enableLocation: Bool) {
        guard !isFinishing else { return }
        isFinishing = true
        Task {
            if enableLocation {
                await session.startTracking()
            }
            do {
                try await selection.commit(using: session)
            } catch {
                // Don't strand the user in onboarding on a write failure — log
                // it and continue; they can re-pick in Settings.
                Self.logger.warning("Failed to commit onboarding region picks")
            }
            model.completeOnboarding()
            bridge.complete()
        }
    }
}

/// One page of the onboarding intro. A plain value (not a view) so the page
/// list reads declaratively and stays easy to reorder.
struct OnboardingPage: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let description: String

    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: "welcome",
            symbol: "globe.americas.fill",
            title: Strings.onboardingWelcomeTitle,
            description: Strings.onboardingWelcomeDescription,
        ),
        OnboardingPage(
            id: "automatic",
            symbol: "location.fill.viewfinder",
            title: Strings.onboardingAutomaticTitle,
            description: Strings.onboardingAutomaticDescription,
        ),
        OnboardingPage(
            id: "privacy",
            symbol: "lock.shield.fill",
            title: Strings.onboardingPrivacyTitle,
            description: Strings.onboardingPrivacyDescription,
        ),
    ]
}

#if DEBUG
    #Preview {
        OnboardingView(bridge: LifecycleStepUIBridge(reason: .userForeground))
            .environment(PreviewSupport.loadedModel())
            .environment(PreviewSupport.loadedSession())
    }
#endif
