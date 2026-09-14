import Foundation
import PortholeCore
import SwiftUI

struct PortholeValueView: View {
    let value: PortholeValue
    @Environment(\.portholeStylesheet) private var stylesheet
    @Environment(\.portholeEvidenceNavigation) private var navigation

    var body: some View {
        let evidence = PortholeEvidenceReference.scan(value)
        VStack(alignment: .leading, spacing: stylesheet.row.spacing) {
            if let navigation, !evidence.links.isEmpty {
                ForEach(evidence.links) { link in
                    PortholeEvidenceLink(reference: link.reference, navigation: navigation)
                        .accessibilityHint("Open evidence at \(link.id.path)")
                }
                DisclosureGroup("Raw value") { rawValue }
            } else { rawValue }
            ForEach(evidence.issues.indices, id: \.self) { index in
                Text(evidence.issues[index]).foregroundStyle(.secondary)
            }
            if evidence
                .truncated
            {
                Text(
                    "Showing the first evidence links. Inspect the raw value for the complete result.",
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var rawValue: some View {
        switch formatted {
            case let .success(text):
                Text(text).font(stylesheet.code.font).textSelection(.enabled)
            case let .failure(error):
                Text("Cannot encode value: \(String(describing: error))")
                    .foregroundStyle(.secondary)
        }
    }

    private var formatted: Result<String, Error> {
        Result {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return try String(decoding: encoder.encode(value), as: UTF8.self)
        }
    }
}

#if DEBUG
    #Preview { PortholeValueView(value: .object([
        "detector": .string("Border drift"),
        "identifiedFlight": .bool(false),
    ])) }
#endif
