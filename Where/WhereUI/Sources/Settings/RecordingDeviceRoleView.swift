import SFSafeSymbols
import SnapshotKit
import SwiftUI
@_spi(Testing) import WhereCore

/// Presents role selection without owning coordination or location work.
struct RecordingDeviceRoleView: View {
    let state: RecordingDeviceRoleModel.State
    let canApprove: Bool
    let choose: (Bool) -> Void
    let retry: () -> Void
    let approve: () -> Void
    let cancel: () -> Void
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
            Text(String(localized: .recordingRoleTitle)).font(.headline)
            switch state {
                case .loading:
                    ProgressView(String(localized: .onboardingRecordingChecking))
                case let .loaded(details):
                    content(details)
                case let .working(details):
                    content(details).disabled(true)
                    ProgressView()
                case let .failed(details, message):
                    if let details { content(details).disabled(true) }
                    Label(message, systemSymbol: .exclamationmarkIcloud)
                    Button(String(localized: .commonRetry), action: retry)
            }
        }
    }

    @ViewBuilder
    private func content(_ details: RecordingDeviceRoleModel.Details) -> some View {
        if details.isOwner {
            Label(String(localized: .recordingRoleThisDevice), systemSymbol: .locationFill)
            if let request = details.authority.pendingHandoff {
                Text(String(localized: .recordingRoleRequest(details
                        .names[request.requestedBy] ??
                        String(localized: .recordingRoleAnotherDevice))))
                if canApprove {
                    Button(String(localized: .recordingRoleApprove), action: approve)
                    Button(String(localized: .commonCancel), role: .cancel, action: cancel)
                }
            } else if details.interruptedApproval != nil {
                Button(String(localized: .commonCancel), role: .cancel, action: cancel)
            }
        } else {
            if let owner = details.authority.owner {
                Text(String(localized: .recordingRoleOwner(details
                        .names[owner.deviceID] ?? String(localized: .recordingRoleAnotherDevice))))
            } else {
                Text(String(localized: .recordingRoleNoOwner))
            }
            if details.isWaiting {
                Text(String(localized: .recordingRoleWaiting))
                Button(String(localized: .recordingRoleCheckAgain), action: retry)
                Button(String(localized: .commonCancel), role: .cancel, action: cancel)
            } else if details.authority.pendingHandoff == nil {
                Button(String(localized: .recordingRoleUseThis)) { choose(true) }
                    .buttonStyle(.borderedProminent)
            } else {
                Text(String(localized: .recordingRoleOtherRequest))
            }
            Button(String(localized: .recordingRoleSecondary)) { choose(false) }
        }
    }
}

#if DEBUG
    extension RecordingDeviceRoleView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            let phone = RecordingDeviceID(rawValue: UUID())
            let tablet = RecordingDeviceID(rawValue: UUID())
            let owner = RecordingAuthority.ownedForTesting(by: phone)
            let requested: RecordingAuthority
            do {
                requested = try RecordingAuthorityProposal(
                    state: owner,
                    action: .requestHandoff,
                    deviceID: tablet,
                    buildVersion: .current,
                    eventID: .init(rawValue: UUID()),
                ).result
            } catch { preconditionFailure("Invalid role snapshot fixture: \(error)") }
            let names = [phone: "iPhone", tablet: "New iPhone"]
            return [
                roleSnapshot(
                    "Unclaimed",
                    configurations: .fullContentScreenDefaults,
                    state: .loaded(.init(
                        authority: .initial,
                        currentDeviceID: phone,
                        names: names,
                    )),
                    canApprove: false,
                ),
                roleSnapshot(
                    "Owner approval",
                    state: .loaded(.init(
                        authority: requested,
                        currentDeviceID: phone,
                        names: names,
                    )),
                    canApprove: true,
                ),
                roleSnapshot(
                    "Waiting",
                    state: .loaded(.init(
                        authority: requested,
                        currentDeviceID: tablet,
                        names: names,
                    )),
                    canApprove: false,
                ),
                roleSnapshot(
                    "Verification failed",
                    state: .failed(nil, RecordingAuthorityError.invalidRecord.localizedDescription),
                    canApprove: false,
                ),
            ]
        }

        private static func roleSnapshot(
            _ name: String,
            configurations: [SnapshotConfiguration] = .fullContentPhoneLightDark,
            state: RecordingDeviceRoleModel.State,
            canApprove: Bool,
        ) -> SnapshotCase {
            whereSnapshot(name: name, configurations: configurations) {
                NavigationStack {
                    Form {
                        Section {
                            RecordingDeviceRoleView(
                                state: state,
                                canApprove: canApprove,
                                choose: { _ in },
                                retry: {},
                                approve: {},
                                cancel: {},
                            )
                        }
                    }.navigationTitle(String(localized: .settingsDevicesTitle))
                }
            }
        }
    }

    #Preview {
        RecordingDeviceRoleView(
            state: .loaded(.init(
                authority: .initial,
                currentDeviceID: .init(rawValue: UUID()),
                names: [:],
            )),
            canApprove: false,
            choose: { _ in },
            retry: {},
            approve: {},
            cancel: {},
        ).padding().whereBroadwayRoot()
    }
#endif
