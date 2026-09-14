import Foundation

/// A complete unified diff. Whole-file hunks preserve trailing-newline changes without an external
/// diff executable.
public enum GitHubPatchReview {
    public static func unifiedDiff(for changes: [GitHubFileChange]) throws -> String {
        try changes.sorted { $0.path < $1.path }.map { change in
            try change.validate()
            var lines =
                [
                    "diff --git \(quoted("a/" + change.path.rawValue)) \(quoted("b/" + change.path.rawValue))",
                ]
            if change.before == nil, let after = change.after {
                lines.append("new file mode \(after.mode.rawValue)")
            } else if change.after == nil, let before = change.before {
                lines.append("deleted file mode \(before.mode.rawValue)")
            } else if let before = change.before, let after = change.after,
                      before.mode != after.mode
            {
                lines += ["old mode \(before.mode.rawValue)", "new mode \(after.mode.rawValue)"]
            }
            if (change.before?.text ?? "") != (change.after?.text ?? "") {
                lines
                    .append(
                        "--- \(change.before == nil ? "/dev/null" : quoted("a/" + change.path.rawValue))",
                    )
                lines
                    .append(
                        "+++ \(change.after == nil ? "/dev/null" : quoted("b/" + change.path.rawValue))",
                    )
                let before = contentLines(change.before?.text ?? "")
                let after = contentLines(change.after?.text ?? "")
                lines
                    .append(
                        "@@ -\(before.isEmpty ? 0 : 1),\(before.count) +\(after.isEmpty ? 0 : 1),\(after.count) @@",
                    )
                append(before, text: change.before?.text, prefix: "-", to: &lines)
                append(after, text: change.after?.text, prefix: "+", to: &lines)
            }
            return lines.joined(separator: "\n") + "\n"
        }.joined()
    }

    private static func contentLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }

    private static func append(
        _ content: [String],
        text: String?,
        prefix: String,
        to lines: inout [String],
    ) {
        lines += content.map { prefix + $0 }
        if !content.isEmpty, text?.hasSuffix("\n") == false {
            lines.append("\\ No newline at end of file")
        }
    }

    private static func quoted(_ path: String) -> String {
        "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
            of: "\"",
            with: "\\\"",
        ) + "\""
    }
}
