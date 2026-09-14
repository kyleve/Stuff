import PortholeCore
import SwiftUI

/// Displays validated handle metadata and candidate APIs without reading native properties.
struct PortholeObjectEvidenceView: View {
    let object: PortholeEvidenceModel.Object
    let navigation: PortholeEvidenceNavigation
    @Environment(\.portholeStylesheet) private var stylesheet

    var body: some View {
        List {
            Section("Recorded object") {
                Text(object.reference.typeName).font(.headline)
                Text(object.reference.id.uuidString).font(stylesheet.code.font)
                    .textSelection(.enabled)
                LabeledContent("Scope", value: object.reference.scope.id.rawValue)
                Text("Generation: \(object.reference.scope.generation.uuidString)")
                    .font(stylesheet.code.font).textSelection(.enabled)
                Text(
                    "Opening this handle does not evaluate properties. Select an API to inspect or change state through its owning executor.",
                )
                .foregroundStyle(.secondary)
            }
            Section {
                if object.capabilities.isEmpty {
                    Text(
                        "No matching generated APIs are registered for this type. Use Explore to find adapters.",
                    )
                    .foregroundStyle(.secondary)
                }
                ForEach(object.capabilities) { capability in
                    NavigationLink {
                        PortholeInvocationView(
                            capability: capability,
                            objects: [object.reference],
                            scope: object.reference.scope,
                            execute: navigation.execute,
                            receiver: object.reference,
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: stylesheet.row.spacing) {
                            PortholeCapabilityLabel(capability: capability)
                            Text(capability.ownership.presentationTitle).font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: { Text("APIs for this recorded type") } footer: {
                Text(
                    "Names identify candidate APIs. The runtime validates the receiver type and scope before a call.",
                )
            }
        }
    }
}
