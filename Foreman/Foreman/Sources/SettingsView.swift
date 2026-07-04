import AppKit
import ForemanCore
import SwiftUI

/// Global settings: where to look for repositories and which `cursor-agent`
/// to run. Values write through the session (which persists and rescans).
struct SettingsView: View {
    let session: ForemanSession
    let onDone: () -> Void

    @State private var scanDirectory: String
    @State private var agentExecutable: String

    init(session: ForemanSession, onDone: @escaping () -> Void) {
        self.session = session
        self.onDone = onDone
        _scanDirectory = State(
            initialValue: session.configuration.scanDirectory?.path ?? "",
        )
        _agentExecutable = State(
            initialValue: session.configuration.agentExecutable?.path ?? "",
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            Form {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan directory")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        TextField(
                            "Scan directory",
                            text: $scanDirectory,
                            prompt: Text("~/Development"),
                        )
                        .labelsHidden()
                        Button("Choose…") { chooseScanDirectory() }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("cursor-agent executable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(
                        "cursor-agent executable",
                        text: $agentExecutable,
                        prompt: Text("Auto-detect"),
                    )
                    .labelsHidden()
                    Text(
                        "Leave empty to search: \(CursorAgentLocator.defaultSearchPaths.joined(separator: ", "))",
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
            .formStyle(.columns)
            .textFieldStyle(.roundedBorder)
            .padding(12)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", action: onDone)
                Button("Save") {
                    save()
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func save() {
        let directory = scanDirectory.trimmingCharacters(in: .whitespaces)
        session.setScanDirectory(
            directory.isEmpty
                ? nil
                : URL(fileURLWithPath: (directory as NSString).expandingTildeInPath),
        )
        let executable = agentExecutable.trimmingCharacters(in: .whitespaces)
        session.setAgentExecutable(
            executable.isEmpty
                ? nil
                : URL(fileURLWithPath: (executable as NSString).expandingTildeInPath),
        )
    }

    private func chooseScanDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = session.configuration.resolvedScanDirectory
        if panel.runModal() == .OK, let url = panel.url {
            scanDirectory = url.path
        }
    }
}

#if DEBUG
    #Preview {
        SettingsView(session: PreviewSupport.emptySession()) {}
            .frame(width: 340)
    }
#endif
