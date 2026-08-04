import LifecycleKit
import LifecycleKitUI
import SnapshotKit
import SwiftUI
import WhereCore

/// Where-specific terminal launch outcomes whose committed effects make the
/// shared “Couldn't finish launching” presentation misleading.
enum WhereLifecycleFailurePresentation: Equatable {
    case committedImportCleanup(BackupCoordinator.ImportSummary)
    case committedImportSetup(BackupCoordinator.ImportSummary)
    case committedResetCleanup

    init?(failure: LifecycleFailure) {
        if let error = failure.error as? BackupCoordinator.CommittedImportCleanupError {
            self = .committedImportCleanup(error.summary)
        } else if let error = failure.error as? OnboardingCommittedImportSetupError {
            self = .committedImportSetup(error.summary)
        } else if failure.error is WhereServices.ResetCleanupError {
            self = .committedResetCleanup
        } else {
            return nil
        }
    }

    var title: String {
        switch self {
            case .committedImportCleanup:
                String(localized: .backupImportCleanupTitle)
            case .committedImportSetup:
                String(localized: .backupImportSetupTitle)
            case .committedResetCleanup:
                String(localized: .launchResetCleanupTitle)
        }
    }

    var message: String {
        switch self {
            case let .committedImportCleanup(summary):
                WhereFormat.backupImportCleanupMessage(summary)
            case let .committedImportSetup(summary):
                WhereFormat.backupImportSetupMessage(summary)
            case .committedResetCleanup:
                String(localized: .launchResetCleanupMessage)
        }
    }

    var systemImage: String {
        switch self {
            case .committedImportCleanup, .committedImportSetup: "exclamationmark.icloud"
            case .committedResetCleanup: "trash.slash"
        }
    }
}

/// Routes ordinary launch failures through LifecycleKit's shared terminal UI,
/// while committed backup/setup/reset failures explain what already succeeded
/// and the safe recovery that remains.
struct WhereLifecycleFailureView: View {
    private enum Content {
        case generic(LifecycleFailure)
        case committed(WhereLifecycleFailurePresentation)
    }

    @Environment(\.stylesheet) private var stylesheet
    private let content: Content

    init(failure: LifecycleFailure) {
        if let presentation = WhereLifecycleFailurePresentation(failure: failure) {
            content = .committed(presentation)
        } else {
            content = .generic(failure)
        }
    }

    #if DEBUG
        init(presentation: WhereLifecycleFailurePresentation) {
            content = .committed(presentation)
        }
    #endif

    var body: some View {
        switch content {
            case let .generic(failure):
                LifecycleFailureView(failure: failure)
            case let .committed(presentation):
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: stylesheet.spacing.large) {
                            Image(systemName: presentation.systemImage)
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(presentation.title)
                                .font(.title.bold())
                                .accessibilityAddTraits(.isHeader)
                            Text(presentation.message)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .padding(stylesheet.spacing.xxxLarge)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .background(Color(.systemBackground).ignoresSafeArea())
        }
    }
}

#if DEBUG
    extension WhereLifecycleFailureView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "CommittedResetCleanup", configurations: .screenDefaults) {
                WhereLifecycleFailureView(presentation: .committedResetCleanup)
            }
            whereSnapshot(name: "CommittedImportCleanup", configurations: .phoneLightDark) {
                WhereLifecycleFailureView(presentation: .committedImportCleanup(.preview))
            }
            whereSnapshot(name: "CommittedImportSetup", configurations: .phoneLightDark) {
                WhereLifecycleFailureView(presentation: .committedImportSetup(.preview))
            }
        }
    }

    extension BackupCoordinator.ImportSummary {
        fileprivate static let preview = BackupCoordinator.ImportSummary(
            sampleCount: 42,
            evidenceCount: 3,
            manualDayCount: 7,
            dismissedIssueCount: 2,
            trackedRegionCount: 5,
            recordingDeviceCount: 2,
            recordingDeviceRemovalCount: 4,
        )
    }

    #Preview {
        WhereLifecycleFailureView.snapshotPreviews
    }

    extension WhereLifecycleFailureView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            WhereLifecycleFailureView.self,
            title: "Committed Operation Failure",
            navigationContainer: .none,
        )
    }
#endif
