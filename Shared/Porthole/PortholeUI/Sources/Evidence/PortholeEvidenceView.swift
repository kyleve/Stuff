import PortholeCore
import SFSafeSymbols
import SwiftUI

extension EnvironmentValues {
    @Entry var portholeEvidenceNavigation: PortholeEvidenceNavigation?
}

struct PortholeEvidenceLink: View {
    let reference: PortholeEvidenceReference
    let navigation: PortholeEvidenceNavigation

    var body: some View {
        NavigationLink {
            PortholeEvidenceView(reference: reference, navigation: navigation)
        } label: {
            Text(reference.title)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One inspector serves references found in explorer, call, console, and chat evidence.
struct PortholeEvidenceView: View {
    @State private var model: PortholeEvidenceModel
    private let navigation: PortholeEvidenceNavigation
    @Environment(\.portholeStylesheet) private var stylesheet

    init(reference: PortholeEvidenceReference, navigation: PortholeEvidenceNavigation) {
        self.init(
            model: PortholeEvidenceModel(reference: reference, reader: navigation.reader),
            navigation: navigation,
        )
    }

    init(model: PortholeEvidenceModel, navigation: PortholeEvidenceNavigation) {
        _model = State(initialValue: model)
        self.navigation = navigation
    }

    var body: some View {
        Group {
            switch model.state {
                case .loading: ProgressView("Opening evidence…")
                case let .failed(message):
                    ScrollView {
                        ContentUnavailableView {
                            Label("Evidence unavailable", systemSymbol: .exclamationmarkTriangle)
                        } description: {
                            Text(message)
                            Text(
                                "Expired handles are not attached to a new scope. The original value remains in the result.",
                            )
                        } actions: {
                            Button("Check again") { Task { await model.load() } }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                    }
                    .defaultScrollAnchor(.center, for: .alignment)
                case let .loaded(content):
                    switch content {
                        case let .object(object): PortholeObjectEvidenceView(
                                object: object,
                                navigation: navigation,
                            )
                        case let .context(context): contextContent(context.capture)
                        case let .source(source): PortholeSourceView(
                                file: source.file,
                                selectedLine: source.line,
                            )
                    }
            }
        }
        .navigationTitle(model.reference.title)
        .portholeInlineNavigationTitle()
        .environment(\.portholeEvidenceNavigation, navigation)
        .task { await model.loadIfNeeded() }
    }

    private func contextContent(_ context: PortholeContext) -> some View {
        List {
            Section("Frozen context") {
                Text(context.title).font(.headline)
                Text(context.capturedAt, format: .dateTime)
                LabeledContent("Scope", value: context.scope.id.rawValue)
                Text(context.scope.generation.uuidString).font(stylesheet.code.font)
                    .textSelection(.enabled)
                PortholeValueView(value: context.values)
            }
            if let source = context.source {
                Section("Captured source location") {
                    PortholeCapturedSourceLink(
                        location: source,
                        scope: context.scope,
                        navigation: navigation,
                    )
                }
            }
            if !context.objects.isEmpty {
                Section("Objects") {
                    ForEach(context.objects, id: \.id) { reference in
                        PortholeEvidenceLink(reference: .object(reference), navigation: navigation)
                    }
                }
            }
            Section("Context relationships") {
                PortholeContextGraphView(
                    graph: .init(context: context, knownContexts: []),
                    navigation: navigation,
                )
            }
        }
    }
}

/// A descriptor without a hash can use only the source captured for its same scope.
struct PortholeCapturedSourceLink: View {
    let location: PortholeSourceLocation
    let scope: PortholeScopeToken
    let navigation: PortholeEvidenceNavigation

    var body: some View {
        PortholeEvidenceLink(
            reference: .sourceLocation(location, scope: scope),
            navigation: navigation,
        )
    }
}
