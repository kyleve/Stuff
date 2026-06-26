import LifecycleKit
import StuffCore
import SwiftUI
import WhereCore

/// First-run onboarding: a short paged intro to the passport concept that
/// culminates in the background-location permission request — the natural
/// place to ask for Always, rather than burying it in Settings.
///
/// Presented as the UI of the launch sequence's interactive `onboarding` step.
/// When the user finishes, it persists `hasOnboarded` and resolves the
/// `LifecycleStepUIBridge` so the launch continues; the existing
/// authorization-sync and tracking-reconcile steps then pick up whatever
/// permission was granted.
public struct OnboardingView: View {
    // Onboarding straddles both: it persists the app-level `hasOnboarded` flag
    // (model) and kicks off background tracking through the session, which the
    // `open-store` step has already built by the time this step runs.
    @Environment(WhereModel.self) private var model
    @Environment(WhereSession.self) private var session
    private let bridge: LifecycleStepUIBridge

    @State private var page = 0
    @State private var isFinishing = false

    public init(bridge: LifecycleStepUIBridge) {
        self.bridge = bridge
    }

    private let pages = OnboardingPage.all

    public var body: some View {
        VStack(spacing: UIConstants.Spacings.xxxLarge) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index])
                        .tag(index)
                        .padding(.horizontal, UIConstants.Spacings.xxxLarge)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            footer
                .padding(.horizontal, UIConstants.Spacings.xxxLarge)
                .padding(.bottom, UIConstants.Spacings.xxxLarge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color.accentColor.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom,
            )
            .ignoresSafeArea(),
        )
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: UIConstants.Spacings.xxxLarge) {
            Spacer(minLength: 0)
            Image(systemName: page.symbol)
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(spacing: UIConstants.Spacings.large) {
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

    @ViewBuilder private var footer: some View {
        if page < pages.count - 1 {
            Button {
                withAnimation { page += 1 }
            } label: {
                Text.localized(LocalizedStrings.Onboarding.continueButton)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            VStack(spacing: UIConstants.Spacings.large) {
                Button {
                    // Request Always-location right here so the system prompt
                    // maps 1:1 to the tap; the launch's tracking-reconcile step
                    // picks up whatever was granted.
                    guard !isFinishing else { return }
                    isFinishing = true
                    Task {
                        await session.startTracking()
                        completeAndContinue()
                    }
                } label: {
                    Text.localized(LocalizedStrings.Onboarding.enableLocation)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(LocalizedStrings.Onboarding.notNow.localized()) {
                    guard !isFinishing else { return }
                    isFinishing = true
                    completeAndContinue()
                }
                .controlSize(.large)
            }
            .disabled(isFinishing)
        }
    }

    /// Persist that onboarding is done and resolve the step's bridge so the
    /// launch continues. Shared by the "Enable Location" and "Not now" taps;
    /// the permission request, when wanted, is made by the button before this.
    private func completeAndContinue() {
        model.completeOnboarding()
        bridge.complete()
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
            title: LocalizedStrings.Onboarding.welcomeTitle.localized(),
            description: LocalizedStrings.Onboarding.welcomeDescription.localized(),
        ),
        OnboardingPage(
            id: "automatic",
            symbol: "location.fill.viewfinder",
            title: LocalizedStrings.Onboarding.automaticTitle.localized(),
            description: LocalizedStrings.Onboarding.automaticDescription.localized(),
        ),
        OnboardingPage(
            id: "privacy",
            symbol: "lock.shield.fill",
            title: LocalizedStrings.Onboarding.privacyTitle.localized(),
            description: LocalizedStrings.Onboarding.privacyDescription.localized(),
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
