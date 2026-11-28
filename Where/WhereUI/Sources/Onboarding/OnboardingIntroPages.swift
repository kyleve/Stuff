import LifecycleKit
import SFSafeSymbols
import SwiftUI
import UniformTypeIdentifiers
@_spi(Testing) import WhereCore

struct OnboardingIntroPages: View {
    @Bindable var flow: OnboardingFlowModel
    @Environment(WhereModel.self) private var model
    @Environment(\.stylesheet) private var stylesheet
    private let pages = OnboardingPage.all

    var body: some View {
        VStack(spacing: stylesheet.spacing.xxxLarge) {
            TabView(selection: $flow.page) {
                ForEach(pages.indices, id: \.self) { index in
                    OnboardingIntroPage(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            OnboardingIntroFooter(flow: flow, pageCount: pages.count, model: model)
                .padding(.horizontal, stylesheet.spacing.xxxLarge)
                .padding(.bottom, stylesheet.spacing.xxxLarge)
                .whereContentRoot()
        }
        .fileImporter(
            isPresented: $flow.showImporter,
            allowedContentTypes: [.zip],
            onCompletion: flow.handleRestoreSelection,
        )
        .confirmationDialog(
            String(localized: .settingsBackupImportStrategyTitle),
            isPresented: $flow.showRestoreStrategyDialog,
            titleVisibility: .visible,
            presenting: flow.restoreSelection.selectedURL,
        ) { _ in
            Button(String(localized: .onboardingRestoreMergeRecommended)) {
                flow.chooseRestoreStrategy(OnboardingRestoreSelection.recommendedStrategy)
            }
            Button(String(localized: .settingsBackupReplace), role: .destructive) {
                flow.chooseRestoreStrategy(.replace)
            }
            Button(String(localized: .settingsDataCancel), role: .cancel) {
                flow.discardPendingRestore()
            }
        } message: { _ in
            Text(String(localized: .settingsBackupImportStrategyMessage))
        }
        .alert(
            flow.failureTitle,
            isPresented: $flow.intro.isShowingFailure,
            presenting: flow.intro.failure,
        ) { _ in
            Button(String(localized: .commonOk), role: .cancel) {}
        } message: { failure in
            // Formatted here rather than stored: the state keeps the error
            // itself, so nothing has to decide how to say it before it's shown.
            Text(failure.error.localizedDescription)
        }
    }
}

private struct OnboardingIntroPage: View {
    let page: OnboardingPage
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: stylesheet.spacing.xxxLarge) {
                Spacer(minLength: 0)
                Image(systemSymbol: page.symbol)
                    .font(stylesheet.typography.onboardingIcon)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                OnboardingHeading(title: Text(page.title), description: Text(page.description))
                // Keep the final line clear of the page indicator while scrolling.
                Spacer(minLength: stylesheet.spacing.xxxLarge)
            }
            .padding(.horizontal, stylesheet.spacing.xxxLarge)
            .frame(minHeight: geometry.size.height)
            .whereScreenRoot(padding: .none)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct OnboardingIntroFooter: View {
    let flow: OnboardingFlowModel
    let pageCount: Int
    let model: WhereModel
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(spacing: stylesheet.spacing.medium) {
            OnboardingContinueButton { withAnimation { flow.advanceIntro(pageCount: pageCount) } }
            // Returning users can skip the manual setup by restoring a backup;
            // the restore's progress replaces the intro with the loading view.
            Button(String(localized: .onboardingRestoreBackup)) { flow.showImporter = true }
                .controlSize(.large)

            // And anyone can look around first, without handing over a
            // location permission or leaving anything on their device.
            Button(String(localized: .onboardingTryDemo)) { flow.enterDemoMode(using: model) }
                .controlSize(.large)
        }
        .disabled(flow.intro.isBuildingDemo)
    }
}

#if DEBUG
    #Preview("Intro and restore") {
        OnboardingView(
            gate: LifecycleGateHandle(id: LaunchStepID.onboarding, reason: .userForeground),
            installationContext: .testing,
        )
        .environment(PreviewSupport.onboardingModel())
        .whereBroadwayRoot()
    }
#endif
