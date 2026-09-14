import PortholeCore
import SwiftUI

struct PortholeCoverageDeclarationView: View {
    let entry: PortholeCoverageEntry
    let scope: PortholeScopeToken
    let capabilities: [PortholeCapability]
    let objects: [PortholeObjectReference]
    let navigation: PortholeEvidenceNavigation
    @Environment(\.portholeStylesheet) private var stylesheet

    var body: some View {
        List {
            Section("Installed build") {
                Text(entry.statusTitle).font(.headline)
                Text(entry.statusReason).fixedSize(horizontal: false, vertical: true)
                LabeledContent("Module", value: entry.module.rawValue)
                Text(entry.declaration.signature).font(stylesheet.code.font).textSelection(.enabled)
                if let capability = entry.callableCapability(in: capabilities) {
                    NavigationLink("Open call form") {
                        PortholeInvocationView(
                            capability: capability,
                            objects: objects,
                            scope: scope,
                            execute: navigation.execute,
                        )
                    }
                }
            }
            Section("Generation plan") {
                Text(entry.plannedSupportTitle)
                if let reason = entry.plannedSupportReason { Text(reason).fixedSize(
                    horizontal: false,
                    vertical: true,
                ) }
                Text(
                    "Planned support describes the generated adapter. It does not establish that this declaration is active in the installed build.",
                )
                .foregroundStyle(.secondary)
            }
            Section("Compilation conditions") {
                if entry.declaration.conditions.isEmpty {
                    Text("No conditional compilation guards were recorded.")
                } else {
                    ForEach(
                        Array(entry.declaration.conditions.enumerated()),
                        id: \.offset,
                    ) { condition in
                        Text(condition.element).font(stylesheet.code.font).textSelection(.enabled)
                    }
                }
            }
            Section("Bundled source") {
                if let reference = entry.sourceEvidence(in: scope) {
                    PortholeEvidenceLink(reference: reference, navigation: navigation)
                } else {
                    Text("No verified source location was packaged for this entry.")
                }
                Text(entry.declaration.id.rawValue).font(stylesheet.code.font)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle(entry.declaration.name)
        .portholeInlineNavigationTitle()
        .environment(\.portholeEvidenceNavigation, navigation)
    }
}

#if DEBUG && canImport(UIKit)
    import SnapshotKit

    #Preview { PortholeCoverageDeclarationView.snapshotPreviews }

    extension PortholeCoverageDeclarationView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Inactive callable plan",
                configurations: SnapshotConfiguration.combinations(
                    devices: [.iPhoneFullContent],
                    colorSchemes: [.light],
                    dynamicTypes: [.large, .accessibility5],
                ),
            ) {
                let services = PortholeCoverageSnapshotServices()
                NavigationStack {
                    PortholeCoverageDeclarationView(
                        entry: PortholeCoverageSnapshotServices.entries[3],
                        scope: PortholeCoverageSnapshotServices.scope,
                        capabilities: [PortholeCoverageSnapshotServices.callable],
                        objects: [],
                        navigation: .init(reader: services, execute: services.invoke),
                    )
                }.portholeBroadwayRoot()
            }
        }
    }
#endif
