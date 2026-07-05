import AppKit
import ForemanCore
import SwiftUI

/// Global settings: where to look for repositories and which `cursor-agent`
/// to run. Hosted by the `Settings` scene (app menu / Cmd-, / the toolbar's
/// `SettingsLink`), so it behaves like a standard macOS settings window:
/// edits apply on field commit (Return / focus change / panel selection) —
/// no Save button. Values write through the session, which persists and
/// rescans.
struct SettingsView: View {
    private enum Field {
        case scanDirectory
        case agentExecutable
    }

    let session: ForemanSession

    @State private var scanDirectory: String
    @State private var agentExecutable: String
    @State private var isWindowVisible = true
    @FocusState private var focusedField: Field?

    init(session: ForemanSession) {
        self.session = session
        _scanDirectory = State(
            initialValue: session.configuration.scanDirectory?.path ?? "",
        )
        _agentExecutable = State(
            initialValue: session.configuration.agentExecutable?.path ?? "",
        )
    }

    var body: some View {
        Form {
            LabeledContent("Scan directory") {
                HStack(spacing: 4) {
                    TextField(
                        "Scan directory",
                        text: $scanDirectory,
                        prompt: Text("~/Development"),
                    )
                    .labelsHidden()
                    .focused($focusedField, equals: .scanDirectory)
                    .onSubmit { applyScanDirectory() }
                    Button("Choose…") { chooseScanDirectory() }
                }
            }

            LabeledContent("cursor-agent") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField(
                        "cursor-agent executable",
                        text: $agentExecutable,
                        prompt: Text("Auto-detect"),
                    )
                    .labelsHidden()
                    .focused($focusedField, equals: .agentExecutable)
                    .onSubmit { applyAgentExecutable() }
                    Text(
                        "Leave empty to search: \(CursorAgentLocator.defaultSearchPaths.joined(separator: ", "))",
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        // Tabbing or clicking out of a field commits it, like Return does.
        .onChange(of: focusedField) { previous, _ in
            switch previous {
                case .scanDirectory: applyScanDirectory()
                case .agentExecutable: applyAgentExecutable()
                case nil: break
            }
        }
        .background(WindowVisibilityReader(isVisible: $isWindowVisible))
        // The Settings window keeps its hierarchy across opens, so init-time
        // drafts go stale; re-seed them whenever the window comes back.
        .onChange(of: isWindowVisible) { _, visible in
            if visible { reseedDrafts() }
        }
    }

    private func reseedDrafts() {
        scanDirectory = session.configuration.scanDirectory?.path ?? ""
        agentExecutable = session.configuration.agentExecutable?.path ?? ""
    }

    private func applyScanDirectory() {
        let directory = parseURL(from: scanDirectory)
        guard directory != session.configuration.scanDirectory else { return }
        session.setScanDirectory(directory)
    }

    private func applyAgentExecutable() {
        let executable = parseURL(from: agentExecutable)
        guard executable != session.configuration.agentExecutable else { return }
        session.setAgentExecutable(executable)
    }

    /// Empty means "use the default" (`nil`); otherwise a tilde-expanded
    /// file URL.
    private func parseURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
    }

    private func chooseScanDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = session.configuration.resolvedScanDirectory
        if panel.runModal() == .OK, let url = panel.url {
            scanDirectory = url.path
            applyScanDirectory()
        }
    }
}

#if DEBUG
    #Preview {
        SettingsView(session: PreviewSupport.emptySession())
    }
#endif
