import LifecycleKit
import SwiftUI
import WhereCore

/// First-run onboarding: a short paged intro to the passport concept that
/// culminates in the background-location permission request — the natural
/// place to ask for Always, rather than burying it in Settings.
///
/// Presented as the UI of the launch sequence's interactive `onboarding` step.
/// When the user finishes, it persists `hasOnboarded` and resolves the
/// `StepHandle` so the launch continues; the existing authorization-sync and
/// tracking-reconcile steps then pick up whatever permission was granted.
public struct OnboardingView: View {
    @Environment(WhereModel.self) private var model
    private let handle: StepHandle

    @State private var page = 0
    @State private var isFinishing = false

    public init(handle: StepHandle) {
        self.handle = handle
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
                Text(Strings.onboardingContinue)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            VStack(spacing: UIConstants.Spacings.large) {
                Button {
                    finish(requestingPermission: true)
                } label: {
                    Text(Strings.onboardingEnableLocation)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(Strings.onboardingNotNow) {
                    finish(requestingPermission: false)
                }
                .controlSize(.large)
            }
            .disabled(isFinishing)
        }
    }

    private func finish(requestingPermission: Bool) {
        guard !isFinishing else { return }
        isFinishing = true
        Task {
            // Requesting permission here is the whole point of asking now; the
            // launch flow's tracking-reconcile step picks up the result.
            if requestingPermission {
                await model.startTracking()
            }
            model.completeOnboarding()
            handle.complete()
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
        OnboardingView(handle: StepHandle(reason: .userForeground))
            .environment(PreviewSupport.loadedModel())
    }
#endif
