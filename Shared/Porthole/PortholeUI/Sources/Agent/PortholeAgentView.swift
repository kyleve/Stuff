import PortholeAgent
#if canImport(UIKit)
    import SnapshotKit
#endif
import SwiftUI

public struct PortholeAgentView: View {
    @Bindable private var model: PortholeAgentPresentationModel
    @Environment(\.portholeStylesheet) private var stylesheet

    public init(model: PortholeAgentPresentationModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            if let investigation = model.investigation {
                Section("Investigation") {
                    Text(investigation.selected.title).font(.headline)
                    Text(investigation.selected.createdAt, style: .date)
                    Text(
                        "This conversation keeps its original capture when you visit another screen.",
                    )
                    .foregroundStyle(.secondary)
                    if !model.hasLiveScope {
                        Text(
                            "This investigation belongs to an earlier app scope. Its evidence is saved, but its live handles are stale. Continue with the current context or start a new investigation.",
                        )
                        .foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Original context") {
                        PortholeValueView(value: investigation.originalContext)
                    }
                    Button("New investigation from current screen", action: model.newInvestigation)
                        .disabled(model.isRunning)
                    Button("Continue with current app context") {
                        Task { await model.continueWithCurrentContext() }
                    }.disabled(model.isRunning)
                    Menu("Resume investigation") {
                        ForEach(investigation.available) { saved in
                            Button {
                                model.resumeInvestigation(saved.id)
                            } label: {
                                Text(
                                    "\(saved.title) — \(saved.createdAt.formatted(date: .abbreviated, time: .shortened))",
                                )
                            }.disabled(saved.id == investigation.selected.id)
                        }
                    }.disabled(model.isRunning || investigation.available.count < 2)
                }
            }
            Section("Provider") {
                Picker("Provider", selection: $model.selectedProvider) {
                    Text("OpenAI").tag(PortholeAgentProvider.openAI)
                    Text("Anthropic").tag(PortholeAgentProvider.anthropic)
                }
                TextField("Model ID", text: $model.modelID).portholeCodeInput()
                SecureField("API key", text: $model.apiKey).portholeCodeInput()
                Button("Save key on this device", action: model.saveKey)
                    .disabled(model.apiKey.isEmpty)
                Button("Remove saved key", role: .destructive, action: model.removeKey)
                Text("Keys stay in this device's Keychain and are excluded from debugger tools.")
                    .foregroundStyle(.secondary)
            }.disabled(model.isRunning)

            Section("Data sharing") {
                Text(
                    "Diagnosis sends your messages, selected app context, tool results, and requested source to the selected provider. Known keys and structured credential fields are removed.",
                )
                if model.hasConsent {
                    Text("Sharing is allowed for \(providerName).")
                    Button("Stop sharing with \(providerName)", role: .destructive) {
                        Task { await model.setConsent(granted: false) }
                    }
                } else {
                    Button("Allow sharing with \(providerName)") {
                        Task { await model.setConsent(granted: true) }
                    }
                }
            }

            if !model.history.isEmpty {
                Section("Conversation") {
                    ForEach(model.history.indices, id: \.self) { index in
                        PortholeAgentMessageView(message: model.history[index])
                    }
                }
            }

            if !model.runs.isEmpty {
                Section {
                    DisclosureGroup("Model history") {
                        ForEach(model.runs, id: \.runID) { run in
                            VStack(alignment: .leading, spacing: stylesheet.row.spacing) {
                                Text("\(run.model.provider.rawValue) / \(run.model.modelID)")
                                    .font(stylesheet.code.font)
                                Text(run.startedAt, style: .date).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            switch model.state {
                case .ready: EmptyView()
                case let .running(progress):
                    Section("Working") {
                        if !progress.text.isEmpty { Text(progress.text).textSelection(.enabled) }
                        if !progress.reasoning.isEmpty {
                            DisclosureGroup("Reasoning") {
                                Text(progress.reasoning).textSelection(.enabled)
                            }
                        }
                        ForEach(progress.toolCalls, id: \.operationID) { invocation in
                            Text("Calling \(invocation.toolID.rawValue)").font(stylesheet.code.font)
                        }
                        Button("Stop", role: .cancel, action: model.cancel)
                    }
                case let .failed(message):
                    Section("Run stopped") { Text(message).textSelection(.enabled) }
                case let .needsReview(review):
                    Section("Operations need review") {
                        Text(
                            "A previous operation has no confirmed outcome. Porthole will not replay it. Check the runtime evidence before continuing.",
                        )
                        if let note = review.note { Text(note).foregroundStyle(.secondary) }
                        ForEach(review.operations, id: \.invocation.operationID) { operation in
                            VStack(alignment: .leading, spacing: stylesheet.row.spacing) {
                                Text(operation.invocation.toolID.rawValue)
                                Text(operation.invocation.operationID.uuidString)
                                    .font(stylesheet.code.font).textSelection(.enabled)
                                PortholeValueView(value: operation.invocation.arguments)
                                Button("Check recorded outcome") {
                                    Task { await model.checkOutcome(operation) }
                                }
                                Button("Acknowledge unknown outcome and continue") {
                                    Task { await model.acknowledgeUncertainty(operation) }
                                }
                            }
                        }
                    }
            }

            Section("Ask Porthole") {
                TextField("Describe the problem", text: $model.prompt, axis: .vertical)
                Button("Diagnose") { Task { await model.send() } }.disabled(!model.canSend)
            }
        }
        .navigationTitle("AI debugger")
        .task { await model.load() }
    }

    private var providerName: String {
        switch model.provider {
            case .openAI: "OpenAI"
            case .anthropic: "Anthropic"
        }
    }
}

#if DEBUG && canImport(UIKit)
    #Preview { PortholeAgentView.snapshotPreviews }
#endif

#if canImport(UIKit)
    extension PortholeAgentView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            SnapshotCase(name: "AgentSetup", configurations: .fullContentScreenDefaults) {
                PortholeAgentSetupSnapshot()
            }
            SnapshotCase(name: "AgentConversation", configurations: .fullContentScreenDefaults) {
                PortholeAgentSetupSnapshot(messages: [
                    .user(text: "Why didn't this identify as a flight?"),
                    .assistant(
                        text: "The recorded endpoints both resolved to the same airport. The flight detector therefore rejected this candidate. Check the endpoint locations before changing the threshold.",
                        toolCalls: [],
                    ),
                ])
            }
        }
    }
#endif
