import Foundation

public enum ReviewMarkdown {
    public static func export(
        suites: [SnapshotSuite],
        root: URL,
        imageIDs: Set<SnapshotImage.ID>?,
    ) throws -> String {
        var lines = ["# Snapshot review todos", ""]
        for suite in suites {
            let file = try suite.reviews.get()
            for review in file.document.images {
                let imageID = SnapshotImage.ID(suite: suite.id, path: review.path)
                if let imageIDs, !imageIDs.contains(imageID) { continue }
                let todos = review.annotations.filter { $0.status == .open }
                guard !todos.isEmpty else { continue }
                let image = suite.images.first { $0.id == imageID }
                let relative = suite.id.appendingPathComponent(review.path.value).path
                    .replacingOccurrences(
                        of: root.path + "/",
                        with: "",
                    )
                lines
                    .append(
                        "## \(suite.id.lastPathComponent) / \(image?.metadata?.caseName ?? review.path.value)",
                    )
                lines.append("Image: `\(relative)`")
                for todo in todos {
                    var suffix = ""
                    if let point = todo.point { suffix += " (point x=\(point.x), y=\(point.y))" }
                    if let image, case let .success(content) = image.content {
                        if todo.fingerprint != content.fingerprint { suffix += " [outdated image]" }
                    } else { suffix += " [image unavailable]" }
                    lines
                        .append(
                            "- [ ] \(todo.text.replacingOccurrences(of: "\n", with: "\n  "))\(suffix)",
                        )
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }
}
