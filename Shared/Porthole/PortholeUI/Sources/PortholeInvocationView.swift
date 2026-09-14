import PortholeRuntime
import SFSafeSymbols
import SwiftUI
#if canImport(UIKit)
    import SnapshotKit
#endif

struct PortholeInvocationView: View {
    @State private var model: PortholeInvocationModel
    private let execute: @MainActor (PortholeInvocation) async throws -> PortholeValue
    private let presentation: PortholePresentationController?
    @Environment(\.portholeStylesheet) private var stylesheet
    @Environment(\.portholeEvidenceNavigation) private var evidenceNavigation
    @Environment(PortholePresentationController
        .self) private var inheritedPresentation: PortholePresentationController?

    init(
        capability: PortholeCapability,
        objects: [PortholeObjectReference],
        scope: PortholeScopeToken,
        controller: PortholePresentationController,
        receiver: PortholeObjectReference? = nil,
    ) {
        self.init(
            capability: capability,
            objects: objects,
            scope: scope,
            execute: controller.execute,
            receiver: receiver,
            presentation: controller,
        )
    }

    init(
        capability: PortholeCapability,
        objects: [PortholeObjectReference],
        scope: PortholeScopeToken,
        execute: @escaping @MainActor (PortholeInvocation) async throws -> PortholeValue,
        receiver: PortholeObjectReference? = nil,
        presentation: PortholePresentationController? = nil,
    ) {
        let model = PortholeInvocationModel(
            capability: capability,
            objects: objects,
            scope: scope,
        )
        model.receiverID = receiver?.id
        self.init(model: model, execute: execute, presentation: presentation)
    }

    init(
        model: PortholeInvocationModel,
        execute: @escaping @MainActor (PortholeInvocation) async throws -> PortholeValue,
        presentation: PortholePresentationController?,
    ) {
        _model = State(initialValue: model)
        self.execute = execute
        self.presentation = presentation
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Capability") {
                Text(model.capability.summary).textSelection(.enabled)
                LabeledContent("Effect", value: model.capability.effect.rawValue.capitalized)
                LabeledContent("Execution", value: model.capability.ownership.presentationTitle)
                if let source = model.capability.source {
                    if let evidenceNavigation {
                        PortholeCapturedSourceLink(
                            location: source,
                            scope: model.scope,
                            navigation: evidenceNavigation,
                        )
                    } else {
                        Text("\(source.path):\(source.line)").font(stylesheet.code.font)
                            .textSelection(.enabled)
                    }
                }
                if case let .unsupported(reason) = model.capability.availability {
                    Label(reason, systemSymbol: .exclamationmarkTriangle)
                }
            }
            if !model.objects.isEmpty {
                Section("Receiver") {
                    Picker("Object", selection: $model.receiverID) {
                        Text("None / static call").tag(UUID?.none)
                        ForEach(model.objects, id: \.id) { object in
                            Text("\(object.typeName) · \(object.id.uuidString.prefix(8))")
                                .tag(Optional(object.id))
                        }
                    }
                    .disabled(model.observation.isActive)
                }
            }
            if !model.fields.isEmpty {
                Section("Arguments") {
                    ForEach(model.fields) { field in argument(field) }
                        .disabled(model.observation.isActive)
                }
            }
            Section {
                Button(model.capability.effect.requiresApproval ? "Review and call" : "Call") {
                    model.run(execute: execute)
                }
                .disabled(!model.isCallable || model.isRunning || model.observation.isActive)
                if model.isRunning { Button("Cancel", role: .cancel) { model.cancel() } }
                if model.canWatch {
                    if model.observation.canStop {
                        Button("Stop watching", role: .cancel) { model.observation.stop() }
                    } else {
                        Button("Watch every second") { model.watch(execute: execute) }
                            .disabled(model.isRunning || model.observation.isActive)
                    }
                }
            }
            Section("Result") { result }
            if model.observation.state.session != nil {
                Section("Watch") { PortholeObservationView(state: model.observation.state) }
            }
        }
        .navigationTitle(model.capability.name)
        .portholeInlineNavigationTitle()
        .onAppear { (presentation ?? inheritedPresentation)?.registerObservation(model.observation)
        }
        .onDisappear {
            model.cancel()
            (presentation ?? inheritedPresentation)?.unregisterObservation(model.observation)
        }
    }

    @ViewBuilder private func argument(_ field: PortholeArgumentField) -> some View {
        @Bindable var field = field
        VStack(alignment: .leading, spacing: stylesheet.row.spacing) {
            switch field.input {
                case .boolean: Toggle(field.parameter.name, isOn: $field.boolean)
                case .integer: TextField(
                        field.parameter.name,
                        text: $field.integerText,
                    )
                    .accessibilityHint("Decimal integer")
                case .number: TextField(field.parameter.name, value: $field.number, format: .number)
                case .string: TextField(field.parameter.name, text: $field.text, axis: .vertical)
                case .json:
                    Text(field.parameter.name)
                    TextEditor(text: $field.text).font(stylesheet.code.font)
                        .frame(minHeight: stylesheet.code.minimumHeight)
                        .accessibilityLabel("\(field.parameter.name) as JSON")
            }
            if !field.parameter.summary.isEmpty {
                Text(field.parameter.summary).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var result: some View {
        switch model.state {
            case .idle: Text("No call has run.").foregroundStyle(.secondary)
            case .running: ProgressView("Waiting for the call or approval…")
            case let .succeeded(value): PortholeValueView(value: value)
            case let .approvalRequired(proposal):
                Text("Approve this exact call on the device, then check its result.")
                Text(proposal.id.uuidString).font(stylesheet.code.font).textSelection(.enabled)
                PortholeValueView(value: proposal.invocation.arguments)
                Button("Check approved call") { model.retryApproved(execute: execute) }
            case let .failed(message): Label(message, systemSymbol: .exclamationmarkTriangle)
            case .cancelled: Text(
                    "Cancellation requested. An operation may already have changed state.",
                )
        }
    }
}

#if canImport(UIKit)
    extension PortholeInvocationView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(name: "CallableRead", configurations: .fullContentScreenDefaults) {
                snapshotForm(effect: .read)
            }
            SnapshotCase(name: "UnknownEffects", configurations: .fullContentScreenDefaults) {
                snapshotForm(effect: .unknown)
            }
            #if DEBUG
                SnapshotCase(
                    name: "ActiveWatchControls",
                    configurations: watchSnapshotConfigurations,
                    settle: .settledAtLeast(minDuration: 1),
                ) {
                    PortholeInvocationSnapshotSurface(stopFails: false)
                }
                SnapshotCase(
                    name: "RetryStopControls",
                    configurations: watchSnapshotConfigurations,
                    settle: .settledAtLeast(minDuration: 1),
                ) {
                    PortholeInvocationSnapshotSurface(stopFails: true)
                }
            #endif
        }

        #if DEBUG
            private static var watchSnapshotConfigurations: [SnapshotConfiguration] {
                SnapshotConfiguration.combinations(
                    devices: [.iPhoneFullContent],
                    colorSchemes: [.light, .dark],
                ) + [.init(dynamicType: .accessibility5, device: .iPhoneFullContent)]
            }
        #endif

        private static func snapshotForm(effect: PortholeEffect) -> some View {
            NavigationStack {
                Self(
                    capability: .init(
                        id: .init(rawValue: "example.inputs"),
                        module: .init(rawValue: "Example"),
                        name: "Detector inputs",
                        summary: "Inspect the inputs for the selected day.",
                        parameters: [.init(
                            name: "day",
                            summary: "Selected calendar day",
                            schema: .string,
                            required: true,
                        )],
                        result: .any,
                        effect: effect,
                        source: nil,
                        ownership: .adapter,
                        availability: .callable,
                    ),
                    objects: [],
                    scope: .init(id: .init(rawValue: "example"), generation: UUID()),
                    execute: { _ in
                        throw PortholeError.unsupported("This preview has no live detector.")
                    },
                )
            }.portholeBroadwayRoot()
        }
    }

    #if DEBUG
        #Preview { PortholeInvocationView.snapshotPreviews }
    #endif
#endif
