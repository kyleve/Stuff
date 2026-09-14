import Foundation
import PortholeRuntime
import SwiftUI

/// Creates the same registry-backed links and inspectors used by debugger results.
struct PortholeEvidencePreviewSurface: View {
    @State private var model: PortholeEvidencePreviewModel

    init(surface: PortholeEvidencePreviewModel.Surface) {
        self.init(model: PortholeEvidencePreviewModel(surface: surface))
    }

    init(model: PortholeEvidencePreviewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            switch model.fixture {
                case nil: ProgressView("Loading evidence…")
                case let .failure(error): Text(error.localizedDescription)
                case let .success(fixture):
                    switch model.surface {
                        case .links:
                            List { PortholeValueView(value: fixture.value) }
                                .environment(
                                    \.portholeEvidenceNavigation,
                                    PortholeEvidenceNavigation(controller: fixture.controller),
                                )
                                .navigationTitle("Recorded result")
                        case .object:
                            PortholeObjectEvidenceView(
                                object: .init(
                                    reference: recordedObject,
                                    capabilities: [fixture.capability],
                                ),
                                navigation: .init(controller: fixture.controller),
                            )
                            .navigationTitle("Recorded object")
                            .portholeInlineNavigationTitle()
                        case .relationships:
                            List {
                                PortholeContextGraphView(
                                    graph: .init(
                                        context: fixture.context,
                                        knownContexts: [fixture.related],
                                    ),
                                    navigation: .init(controller: fixture.controller),
                                )
                            }
                            .navigationTitle("Context relationships")
                        case .expired:
                            PortholeEvidenceView(
                                model: fixture.evidence,
                                navigation: .init(controller: fixture.controller),
                            )
                    }
            }
        }
        .portholeBroadwayRoot()
        .task { await model.prepare() }
    }

    private var recordedObject: PortholeObjectReference {
        PortholeObjectReference(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
            scope: PortholeScopeToken(
                id: .init(rawValue: "flight-investigation"),
                generation: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)),
            ),
            typeName: "PortholeUI.PortholeEvidencePreviewActor",
        )
    }
}
