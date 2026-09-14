import PortholeAgent
import SwiftUI

struct PortholeAgentMessageView: View {
    let message: PortholeAgentMessage
    @Environment(\.portholeStylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.row.spacing) {
            switch message {
                case let .user(text):
                    Text("You").font(.headline)
                    Text(text).textSelection(.enabled)
                case let .assistant(text, calls):
                    Text("Porthole").font(.headline)
                    if !text.isEmpty { Text(text).textSelection(.enabled) }
                    ForEach(calls, id: \.operationID) { call in
                        DisclosureGroup("Call: \(call.toolID.rawValue)") {
                            Text(call.operationID.uuidString).font(stylesheet.code.font)
                                .textSelection(.enabled)
                            PortholeValueView(value: call.arguments)
                        }
                    }
                case let .tool(results):
                    ForEach(results, id: \.callID) { result in
                        DisclosureGroup(
                            "\(result.isError ? "Error" : "Evidence"): \(result.toolID.rawValue)",
                        ) {
                            PortholeValueView(value: result.output)
                        }
                    }
            }
        }
    }
}

#if DEBUG
    #Preview { PortholeAgentMessageView(message: .assistant(
        text: "The flight detector rejected the endpoints because both map to the same airport.",
        toolCalls: [],
    )) }
#endif
