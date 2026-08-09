import Foundation

/// Parses GitHub's per-file unified patch into stable, renderer-ready hunks.
public struct UnifiedPatchParser: Sendable {
    public init() {}

    public func parse(_ patch: String, path: String) throws -> [DiffHunk] {
        let sourceLines = patch.split(separator: "\n", omittingEmptySubsequences: false)
        var hunks: [DiffHunk] = []
        var cursor = 0

        while cursor < sourceLines.count {
            let candidate = String(sourceLines[cursor])
            guard candidate.hasPrefix("@@") else {
                cursor += 1
                continue
            }

            let header = try parseHeader(candidate)
            let hunkIndex = hunks.count
            cursor += 1
            var oldLine = header.oldStart
            var newLine = header.newStart
            var lines: [DiffLine] = []

            while cursor < sourceLines.count {
                let rawLine = String(sourceLines[cursor])
                if rawLine.hasPrefix("@@") { break }

                let id = DiffLine.ID(rawValue: "\(path):\(hunkIndex):\(lines.count)")
                if rawLine.hasPrefix("+") {
                    lines.append(DiffLine(
                        id: id,
                        kind: .addition,
                        oldLine: nil,
                        newLine: newLine,
                        text: String(rawLine.dropFirst()),
                    ))
                    newLine += 1
                } else if rawLine.hasPrefix("-") {
                    lines.append(DiffLine(
                        id: id,
                        kind: .deletion,
                        oldLine: oldLine,
                        newLine: nil,
                        text: String(rawLine.dropFirst()),
                    ))
                    oldLine += 1
                } else if rawLine.hasPrefix(" ") {
                    lines.append(DiffLine(
                        id: id,
                        kind: .context,
                        oldLine: oldLine,
                        newLine: newLine,
                        text: String(rawLine.dropFirst()),
                    ))
                    oldLine += 1
                    newLine += 1
                } else if rawLine.hasPrefix("\\") {
                    lines.append(DiffLine(
                        id: id,
                        kind: .metadata,
                        oldLine: nil,
                        newLine: nil,
                        text: rawLine,
                    ))
                } else {
                    throw UnifiedPatchError.invalidLine
                }
                cursor += 1
            }

            hunks.append(DiffHunk(
                id: DiffHunk.ID(rawValue: "\(path):\(hunkIndex)"),
                header: candidate,
                oldStart: header.oldStart,
                oldCount: header.oldCount,
                newStart: header.newStart,
                newCount: header.newCount,
                lines: lines,
            ))
        }

        guard !hunks.isEmpty || patch.isEmpty else {
            throw UnifiedPatchError.missingHunkHeader
        }
        return hunks
    }

    private func parseHeader(_ header: String) throws -> Header {
        // Split the range tokens rather than relying on a permissive regex;
        // malformed GitHub payloads fail closed instead of shifting anchors.
        let tokens = header.split(separator: " ", omittingEmptySubsequences: true)
        guard tokens.count >= 3, tokens[0] == "@@", tokens[1].hasPrefix("-"),
              tokens[2].hasPrefix("+")
        else {
            throw UnifiedPatchError.invalidHunkHeader
        }
        let old = try parseRange(tokens[1].dropFirst())
        let new = try parseRange(tokens[2].dropFirst())
        return Header(
            oldStart: old.start,
            oldCount: old.count,
            newStart: new.start,
            newCount: new.count,
        )
    }

    private func parseRange(_ token: Substring) throws -> (start: Int, count: Int) {
        let parts = token.split(separator: ",", omittingEmptySubsequences: false)
        guard let start = Int(parts[0]), start >= 0, parts.count <= 2 else {
            throw UnifiedPatchError.invalidHunkHeader
        }
        let count: Int
        if parts.count == 2 {
            guard let parsed = Int(parts[1]), parsed >= 0 else {
                throw UnifiedPatchError.invalidHunkHeader
            }
            count = parsed
        } else {
            count = 1
        }
        return (start, count)
    }

    private struct Header {
        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
    }
}

public enum UnifiedPatchError: LocalizedError, Equatable, Sendable {
    case missingHunkHeader
    case invalidHunkHeader
    case invalidLine

    public var errorDescription: String? {
        switch self {
            case .missingHunkHeader:
                "GitHub returned a patch without a hunk header."
            case .invalidHunkHeader:
                "GitHub returned a malformed patch hunk header."
            case .invalidLine:
                "GitHub returned a malformed patch line."
        }
    }
}
