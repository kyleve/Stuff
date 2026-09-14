import SFSafeSymbols
import SwiftUI
#if canImport(UIKit)
    import SnapshotKit
#endif

/// The reusable debugger surface. Its host owns the registry and captured origin.
public struct PortholeView: View {
    @Bindable private var controller: PortholePresentationController

    public init(controller: PortholePresentationController) {
        self.controller = controller
    }

    public var body: some View {
        TabView {
            Tab("Explore", systemSymbol: .viewfinder) {
                NavigationStack { PortholeExplorerView(controller: controller).toolbar { close } }
            }
            Tab("Source", systemSymbol: .textDocument) {
                NavigationStack {
                    PortholeSourceBrowserView(controller: controller).toolbar { close }
                }
            }
            Tab("Console", systemSymbol: .appleTerminal) {
                NavigationStack { PortholeConsoleView(
                    model: controller.console,
                    controller: controller,
                ).toolbar { close } }
            }
            Tab("Review", systemSymbol: .checkmarkShield) {
                NavigationStack { PortholeApprovalView(controller: controller).toolbar { close } }
            }
            .badge(controller.pendingApprovals.count)
            if let agent = controller.agent {
                Tab("Ask", systemSymbol: .sparkles) {
                    NavigationStack { PortholeAgentView(model: agent).toolbar { close } }
                }
            } else if let message = controller.agentConfigurationError {
                Tab("Ask", systemSymbol: .sparkles) {
                    NavigationStack {
                        PortholeAgentConfigurationFailureView(
                            message: message,
                            retry: controller.retryAgentConfiguration,
                        ).toolbar { close }
                    }
                }
            }
            if let host = controller.host {
                Tab("Remote", systemSymbol: .network) {
                    NavigationStack { PortholeHostingView(model: host).toolbar { close } }
                }
            }
            if let github = controller.github {
                Tab("Fix", systemSymbol: .arrowTriangleheadBranch) {
                    NavigationStack { PortholeGitHubView(model: github).toolbar { close } }
                }
            } else if let message = controller.githubConfigurationError {
                Tab("Fix", systemSymbol: .arrowTriangleheadBranch) {
                    NavigationStack {
                        ContentUnavailableView {
                            Label("Repository setup failed", systemSymbol: .exclamationmarkTriangle)
                        } description: { Text(message) }
                            .toolbar { close }
                    }
                }
            }
        }
        .portholeBroadwayRoot()
        .environment(controller)
        .environment(
            \.portholeEvidenceNavigation,
            PortholeEvidenceNavigation(controller: controller),
        )
        .task(id: controller.sessionID) { await controller.refreshIfNeeded() }
        .task(id: controller.sessionID) { await controller.observeApprovals() }
        .onDisappear { controller.console.cancel() }
    }

    @ToolbarContentBuilder private var close: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { controller.dismiss() }
        }
    }
}

#if DEBUG && canImport(UIKit)
    #Preview { PortholeView.snapshotPreviews }
#endif

#if canImport(UIKit)
    extension PortholeView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            let capturedIssue = PortholePreviewModel()
            let expiredEvidence = PortholeEvidencePreviewModel(surface: .expired)
            SnapshotCase(
                name: "CapturedIssue",
                configurations: .fullContentScreenDefaults,
                onReadyToMeasure: { await capturedIssue.prepare() },
                settle: .settledAtLeast(minDuration: 1),
                onReadyToSnapshot: { await capturedIssue.prepare() },
            ) {
                PortholePreviewSurface(model: capturedIssue)
            }
            SnapshotCase(
                name: "EvidenceLinks",
                configurations: .fullContentScreenDefaults,
                settle: .settledAtLeast(minDuration: 1),
            ) {
                PortholeEvidencePreviewSurface(surface: .links)
            }
            SnapshotCase(
                name: "ObjectEvidence",
                configurations: .fullContentScreenDefaults,
                settle: .settledAtLeast(minDuration: 1),
            ) {
                PortholeEvidencePreviewSurface(surface: .object)
            }
            SnapshotCase(
                name: "ExpiredEvidence",
                configurations: .fullContentScreenDefaults,
                onReadyToMeasure: { await expiredEvidence.prepare() },
                onReadyToSnapshot: { await expiredEvidence.prepare() },
            ) {
                PortholeEvidencePreviewSurface(model: expiredEvidence)
            }
            SnapshotCase(
                name: "ContextRelationships",
                configurations: .fullContentScreenDefaults,
                settle: .settledAtLeast(minDuration: 1),
            ) {
                PortholeEvidencePreviewSurface(surface: .relationships)
            }
            SnapshotCase(
                name: "SourceEvidence",
                configurations: SnapshotConfiguration.combinations(
                    devices: [.iPhoneFullContent2D, .iPadFullContent2D],
                    colorSchemes: [.light, .dark],
                    dynamicTypes: [.large, .accessibility5],
                ),
            ) {
                NavigationStack {
                    PortholeSourceView(
                        file: .init(
                            path: "Example/FlightDetector.swift",
                            content: "func identifyFlight() -> Bool {\n    // The recorded endpoint airports are equal.\n    false\n}",
                        ),
                        selectedLine: 3,
                    )
                }
                .portholeBroadwayRoot()
            }
        }
    }
#endif
