import ForemanCore
import SwiftUI

/// Editor for one repo's `WorkerOptions`. Edits a local draft and writes back
/// through the session on Save; the row only offers this screen while the
/// worker is stopped, so changes always apply to the next start.
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

    let session: ForemanSession
    let repo: Repo
    let onDone: () -> Void

    @State private var draft: Draft

    init(session: ForemanSession, repo: Repo, onDone: @escaping () -> Void) {
        self.session = session
        self.repo = repo
        self.onDone = onDone
        _draft = State(initialValue: Draft(session.configuration.options(for: repo.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(repo.name)
                    .font(.headline)
                Spacer()
                Text("Worker Options")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            Form {
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
            .formStyle(.columns)
            .textFieldStyle(.roundedBorder)
            .padding(12)

            Divider()

            HStack {
                Button("Reset to Defaults") {
                    draft = Draft(.standard)
                }
                Spacer()
                Button("Cancel", action: onDone)
                Button("Save") {
                    session.updateOptions(draft.options, for: repo)
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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
        .padding(.top, 4)
    }
}

#if DEBUG
    #Preview {
        let session = PreviewSupport.populatedSession()
        return WorkerOptionsView(session: session, repo: session.rows[0].repo) {}
            .frame(width: 340)
    }
#endif
