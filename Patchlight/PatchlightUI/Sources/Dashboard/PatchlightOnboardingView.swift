import PatchlightCore
import SnapshotKit
import SwiftUI
import UIKit

struct PatchlightOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot
    @Environment(\.openURL) private var openURL
    let model: PatchlightAppModel
    @State private var showsAISettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch model.accountState {
                        case .signedOut:
                            introduction
                        case let .connecting(authorization):
                            if let authorization {
                                deviceCode(authorization)
                            } else {
                                ProgressView(String(localized: .requestingDeviceCode))
                            }
                        case .loading:
                            ProgressView(String(localized: .loadingGitHub))
                        case .ready:
                            completed
                        case .reauthorization:
                            introduction
                        case let .failed(_, message):
                            failure(message)
                    }
                }
                .padding(40)
                .frame(maxWidth: 680, minHeight: 500)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .cancel)) {
                        model.cancelAuthorization()
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showsAISettings) {
            PatchlightAISettingsView(model: model)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(String(localized: .connectToGitHub))
                .font(.largeTitle.bold())
            Text(String(localized: .githubOnboardingDescription))
                .font(.title3)
                .foregroundStyle(.secondary)
            Label(String(localized: .githubPermissionsSummary), systemImage: "lock.shield")
                .foregroundStyle(.secondary)
            Spacer()
            Button(String(localized: .beginDeviceSignIn)) {
                model.startAuthorization()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func deviceCode(_ authorization: GitHubDeviceAuthorization) -> some View {
        VStack(spacing: 24) {
            Label(String(localized: .openGitHubDevice), systemImage: "safari")
                .font(.title2.bold())
            Text(authorization.verificationURL.absoluteString)
                .font(.body.monospaced())
                .textSelection(.enabled)
            Text(authorization.userCode)
                .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                .textSelection(.enabled)
                .accessibilityLabel(String(localized: .githubDeviceCode))
                .accessibilityValue(authorization.userCode)
            if isCapturingSnapshot {
                Text(verbatim: "10:00")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(String(
                        localized: "tenMinutesRemaining",
                        defaultValue: "10 minutes remaining",
                    ))
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(
                        timerInterval: context.date ... max(context.date, authorization.expiresAt),
                        countsDown: true,
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button(String(localized: .copyCode)) {
                    UIPasteboard.general.string = authorization.userCode
                }
                .buttonStyle(.bordered)
                Button(String(localized: .openGitHub)) {
                    openURL(authorization.verificationURL)
                }
                .buttonStyle(.borderedProminent)
            }
            if isCapturingSnapshot {
                Label(String(localized: .waitingForGitHub), systemImage: "progress.indicator")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView(String(localized: .waitingForGitHub))
            }
            Text(String(localized: .deviceFlowCanCancel))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    private var completed: some View {
        ContentUnavailableView {
            Label(String(localized: .githubConnected), systemImage: "checkmark.circle.fill")
        } description: {
            VStack {
                Text(String(localized: .githubConnectedDescription))
                Text(String(
                    localized: "optionalAIOnboarding",
                    defaultValue: "Optional: add an OpenAI or Anthropic key now, or keep using Patchlight without AI.",
                ))
            }
        } actions: {
            Button(String(localized: "configureAI", defaultValue: "Configure AI")) {
                showsAISettings = true
            }
            Button(String(localized: .continueAction)) { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label(
                String(localized: .couldNotConnectGitHub),
                systemImage: "exclamationmark.triangle",
            )
        } description: {
            Text(message)
        } actions: {
            Button(String(localized: .tryAgain)) { model.startAuthorization() }
                .buttonStyle(.borderedProminent)
        }
    }
}

#if DEBUG
    @_spi(Testing)
    @MainActor
    public enum PatchlightOnboardingSnapshots: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Introduction",
                configurations: [
                    SnapshotConfiguration(device: .iPadFullContent),
                    SnapshotConfiguration(colorScheme: .dark, device: .iPadFullContent),
                ],
                settle: .immediate,
            ) {
                PatchlightOnboardingView(model: PatchlightVisualFixtures.dashboardModel(.signedOut))
                    .patchlightBroadwayRoot()
            }
            SnapshotCase(
                name: "DeviceCode",
                configurations: [SnapshotConfiguration(device: .iPadFullContent)],
                settle: .immediate,
            ) {
                PatchlightOnboardingView(model: PatchlightVisualFixtures.dashboardModel(
                    .connecting(deviceAuthorization),
                ))
                .patchlightBroadwayRoot()
            }
        }

        private static var deviceAuthorization: GitHubDeviceAuthorization {
            guard let url = URL(string: "https://github.com/login/device") else {
                preconditionFailure("GitHub's device authorization URL must be valid")
            }
            return GitHubDeviceAuthorization(
                deviceCode: "visual-fixture-device-code",
                userCode: "PL42-LOOK",
                verificationURL: url,
                expiresAt: Date.now.addingTimeInterval(600),
                pollingInterval: .seconds(5),
            )
        }
    }

    #Preview {
        PatchlightOnboardingSnapshots.snapshotPreviews
    }
#endif
