import ForemanCore
import SwiftUI

/// Inline editor for one repo's `WorkerOptions` — a `Section` for the worker
/// detail form. Edits a local draft and writes back to `repo.options` on
/// Save (Core persists). Locked (all controls disabled) while the worker is
/// live: options apply at spawn, so mid-run edits would silently do nothing
/// until a restart.
struct WorkerOptionsView: View {
    /// `WorkerOptions` reshaped for form binding: optionals become empty
    /// strings, the pool case splits into a toggle + name, labels get stable
    /// identities for `ForEach`.
    private struct Draft {
        struct LabelDraft: Identifiable {
            let id = UUID()
            var key = ""
            var value = ""
        }

        var displayName = ""
        var isPool = false
        var poolName = ""
        var labels: [LabelDraft] = []
        var idleReleaseTimeoutSeconds = 0
        var verbose = false

        init(_ options: WorkerOptions) {
            displayName = options.displayName ?? ""
            switch options.assignment {
                case .shared:
                    isPool = false
                case let .pool(name):
                    isPool = true
                    poolName = name
            }
            labels = options.labels.map { LabelDraft(key: $0.key, value: $0.value) }
            idleReleaseTimeoutSeconds = options.idleReleaseTimeoutSeconds
            verbose = options.verbose
        }

        var options: WorkerOptions {
            WorkerOptions(
                displayName: displayName.isEmpty ? nil : displayName,
                assignment: isPool ? .pool(name: poolName) : .shared,
                labels: labels
                    .filter { !$0.key.isEmpty }
                    .map { WorkerOptions.Label(key: $0.key, value: $0.value) },
                idleReleaseTimeoutSeconds: max(0, idleReleaseTimeoutSeconds),
                verbose: verbose,
            )
        }
    }

    let repo: Repo
    let isLocked: Bool

    @State private var draft: Draft

    init(repo: Repo, isLocked: Bool) {
        self.repo = repo
        self.isLocked = isLocked
        _draft = State(initialValue: Draft(repo.options))
    }

    private var isDirty: Bool {
        draft.options != repo.options
    }

    var body: some View {
        Section {
            Group {
                TextField("Worker name", text: $draft.displayName, prompt: Text("Host name"))

                Toggle("Pool worker (one agent at a time)", isOn: $draft.isPool)
                if draft.isPool {
                    TextField("Pool name", text: $draft.poolName, prompt: Text("default"))
                }

                TextField(
                    "Idle release (seconds)",
                    value: $draft.idleReleaseTimeoutSeconds,
                    format: .number,
                    prompt: Text("0 = never"),
                )

                Toggle("Verbose startup logs", isOn: $draft.verbose)

                labelsSection
            }
            .disabled(isLocked)

            HStack {
                Button("Reset to Defaults") {
                    draft = Draft(.standard)
                }
                .disabled(isLocked)
                Spacer()
                Button("Revert") {
                    draft = Draft(repo.options)
                }
                .disabled(isLocked || !isDirty)
                Button("Save") {
                    repo.options = draft.options
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isLocked || !isDirty)
            }
            .controlSize(.small)
        } header: {
            Text("Options")
        } footer: {
            if isLocked {
                Text("Stop the worker to edit — options apply on the next start.")
            }
        }
    }

    private var labelsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Labels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    draft.labels.append(Draft.LabelDraft())
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add a key=value label for this worker.")
            }
            ForEach($draft.labels) { $label in
                HStack(spacing: 4) {
                    TextField("key", text: $label.key)
                    Text("=")
                        .foregroundStyle(.secondary)
                    TextField("value", text: $label.value)
                    Button {
                        draft.labels.removeAll { $0.id == label.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

#if DEBUG
    #Preview {
        let session = PreviewSupport.populatedSession()
        return Form {
            WorkerOptionsView(repo: session.repos[0], isLocked: false)
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
#endif
