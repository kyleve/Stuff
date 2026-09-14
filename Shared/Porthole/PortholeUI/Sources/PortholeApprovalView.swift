import PortholeCore
import SwiftUI

struct PortholeApprovalView: View {
    let controller: PortholePresentationController

    var body: some View {
        List {
            if controller.pendingApprovals.isEmpty {
                Text("No operations are waiting for approval.").foregroundStyle(.secondary)
            }
            ForEach(controller.pendingApprovals) { proposal in
                Section(proposal.capability.name) {
                    LabeledContent("Effect", value: proposal.capability.effect.rawValue)
                    LabeledContent("Scope", value: proposal.invocation.scope.id.rawValue)
                    if let receiver = proposal.invocation.receiver { Text(receiver.typeName) }
                    PortholeValueView(value: proposal.invocation.arguments)
                    Text("This approval applies only to these arguments and this operation.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Approve and run") { Task { await controller.approve(proposal) } }
                    Button("Reject", role: .destructive) {
                        controller.reject(operationID: proposal.id)
                    }
                }
            }
            if let error = controller.approvalError { Text(error).foregroundStyle(.secondary) }
        }
        .navigationTitle("Review operations")
    }
}
