import PortholeCore
import SwiftUI

struct PortholeSourceView: View {
    struct Line: Identifiable {
        let number: Int
        let text: String
        var id: Int {
            number
        }
    }

    let file: PortholeSourceFile
    let lines: [Line]
    let selectedLine: Int
    @Environment(\.portholeStylesheet) private var stylesheet

    init(file: PortholeSourceFile, selectedLine: Int = 1) {
        self.file = file
        self.selectedLine = selectedLine
        lines = file.content.components(separatedBy: "\n").enumerated().map { Line(
            number: $0.offset + 1,
            text: $0.element,
        ) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.row.spacing) {
            Text("SHA-256: \(file.sha256)").font(stylesheet.code.font).textSelection(.enabled)
                .padding(.horizontal, stylesheet.row.padding)
            if !lines.contains(where: { $0.number == selectedLine }) {
                Text("Line \(selectedLine) is outside this source file.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, stylesheet.row.padding)
            }
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: stylesheet.row.spacing) {
                        ForEach(lines) { line in
                            HStack(alignment: .top, spacing: stylesheet.row.spacing) {
                                Text(line.number, format: .number.grouping(.never))
                                    .foregroundStyle(.secondary)
                                Text(line.text.isEmpty ? " " : line.text).textSelection(.enabled)
                            }
                            .fontWeight(line.number == selectedLine ? .semibold : .regular)
                            .id(line.number)
                        }
                    }
                    .font(stylesheet.code.font)
                    .padding(stylesheet.row.padding)
                }
                .task(id: selectedLine) { proxy.scrollTo(selectedLine, anchor: .topLeading) }
            }
        }
        .navigationTitle(file.path)
        .portholeInlineNavigationTitle()
    }
}

#if DEBUG
    #Preview { NavigationStack { PortholeSourceView(file: .init(
        path: "Detector.swift",
        content: "func identifyFlight() -> Bool {\n    false\n}",
    )) } }
#endif
