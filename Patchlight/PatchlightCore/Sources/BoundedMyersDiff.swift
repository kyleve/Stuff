import Foundation

public struct LineDiffLimits: Hashable, Sendable {
    public let maximumBytesPerSide: Int
    public let maximumLinesPerSide: Int
    public let maximumWork: Int

    public init(
        maximumBytesPerSide: Int,
        maximumLinesPerSide: Int,
        maximumWork: Int,
    ) {
        precondition(maximumBytesPerSide > 0)
        precondition(maximumLinesPerSide > 0)
        precondition(maximumWork > 0)
        self.maximumBytesPerSide = maximumBytesPerSide
        self.maximumLinesPerSide = maximumLinesPerSide
        self.maximumWork = maximumWork
    }

    public static let githubFallback = LineDiffLimits(
        maximumBytesPerSide: 2 * 1024 * 1024,
        maximumLinesPerSide: 20000,
        maximumWork: 8_000_000,
    )
}

/// A cancellable Myers line diff whose byte, line, and search-work ceilings
/// turn pathological files into honest metadata instead of UI stalls.
public struct BoundedMyersDiff: Sendable {
    private let limits: LineDiffLimits
    private let contextLineCount: Int

    public init(limits: LineDiffLimits, contextLineCount: Int) {
        precondition(contextLineCount >= 0)
        self.limits = limits
        self.contextLineCount = contextLineCount
    }

    public func diff(base: Data, head: Data, path: String) throws -> [DiffHunk] {
        guard base.count <= limits.maximumBytesPerSide,
              head.count <= limits.maximumBytesPerSide
        else {
            throw BoundedMyersDiffError.tooLarge(baseBytes: base.count, headBytes: head.count)
        }
        guard !base.contains(0), !head.contains(0),
              let baseText = String(data: base, encoding: .utf8),
              let headText = String(data: head, encoding: .utf8)
        else {
            throw BoundedMyersDiffError.undecodable
        }

        let baseLines = Self.lines(in: baseText)
        let headLines = Self.lines(in: headText)
        guard baseLines.count <= limits.maximumLinesPerSide,
              headLines.count <= limits.maximumLinesPerSide
        else {
            throw BoundedMyersDiffError.tooManyLines(
                base: baseLines.count,
                head: headLines.count,
            )
        }

        let operations = try operations(base: baseLines, head: headLines)
        return hunks(from: operations, path: path)
    }

    private func operations(base: [String], head: [String]) throws -> [Operation] {
        if base == head { return base.map(Operation.equal) }

        let maximum = base.count + head.count
        var frontier = [1: 0]
        var trace: [[Int: Int]] = []
        var work = 0

        for distance in 0 ... maximum {
            try Task.checkCancellation()
            trace.append(frontier)
            var next = frontier
            for diagonal in stride(from: -distance, through: distance, by: 2) {
                work += 1
                guard work <= limits.maximumWork else {
                    throw BoundedMyersDiffError.workLimitExceeded
                }

                let x: Int = if diagonal == -distance ||
                    (diagonal != distance &&
                        frontier[diagonal - 1, default: -1] < frontier[diagonal + 1, default: -1])
                {
                    frontier[diagonal + 1, default: 0]
                } else {
                    frontier[diagonal - 1, default: 0] + 1
                }
                var advancedX = x
                var advancedY = advancedX - diagonal
                while advancedX < base.count, advancedY < head.count,
                      base[advancedX] == head[advancedY]
                {
                    advancedX += 1
                    advancedY += 1
                    work += 1
                    if work.isMultiple(of: 2048) {
                        try Task.checkCancellation()
                    }
                    guard work <= limits.maximumWork else {
                        throw BoundedMyersDiffError.workLimitExceeded
                    }
                }
                next[diagonal] = advancedX
                if advancedX >= base.count, advancedY >= head.count {
                    return backtrack(
                        trace: trace,
                        distance: distance,
                        base: base,
                        head: head,
                    )
                }
            }
            frontier = next
        }
        throw BoundedMyersDiffError.workLimitExceeded
    }

    private func backtrack(
        trace: [[Int: Int]],
        distance: Int,
        base: [String],
        head: [String],
    ) -> [Operation] {
        var x = base.count
        var y = head.count
        var reversed: [Operation] = []

        guard distance > 0 else { return base.map(Operation.equal) }
        for depth in stride(from: distance, through: 1, by: -1) {
            let frontier = trace[depth]
            let diagonal = x - y
            let previousDiagonal: Int = if diagonal == -depth ||
                (diagonal != depth &&
                    frontier[diagonal - 1, default: -1] < frontier[diagonal + 1, default: -1])
            {
                diagonal + 1
            } else {
                diagonal - 1
            }
            let previousX = frontier[previousDiagonal, default: 0]
            let previousY = previousX - previousDiagonal

            while x > previousX, y > previousY {
                reversed.append(.equal(base[x - 1]))
                x -= 1
                y -= 1
            }

            if x == previousX {
                reversed.append(.insert(head[y - 1]))
                y -= 1
            } else {
                reversed.append(.delete(base[x - 1]))
                x -= 1
            }
        }
        while x > 0, y > 0 {
            reversed.append(.equal(base[x - 1]))
            x -= 1
            y -= 1
        }
        while x > 0 {
            reversed.append(.delete(base[x - 1]))
            x -= 1
        }
        while y > 0 {
            reversed.append(.insert(head[y - 1]))
            y -= 1
        }
        return reversed.reversed()
    }

    private func hunks(from operations: [Operation], path: String) -> [DiffHunk] {
        var rows: [Row] = []
        var oldPosition = 0
        var newPosition = 0
        for operation in operations {
            let beforeOld = oldPosition
            let beforeNew = newPosition
            switch operation {
                case let .equal(text):
                    oldPosition += 1
                    newPosition += 1
                    rows.append(Row(
                        kind: .context,
                        text: text,
                        oldLine: oldPosition,
                        newLine: newPosition,
                        oldPositionBefore: beforeOld,
                        newPositionBefore: beforeNew,
                    ))
                case let .delete(text):
                    oldPosition += 1
                    rows.append(Row(
                        kind: .deletion,
                        text: text,
                        oldLine: oldPosition,
                        newLine: nil,
                        oldPositionBefore: beforeOld,
                        newPositionBefore: beforeNew,
                    ))
                case let .insert(text):
                    newPosition += 1
                    rows.append(Row(
                        kind: .addition,
                        text: text,
                        oldLine: nil,
                        newLine: newPosition,
                        oldPositionBefore: beforeOld,
                        newPositionBefore: beforeNew,
                    ))
            }
        }

        let changed = rows.indices.filter { rows[$0].kind != .context }
        guard let first = changed.first else { return [] }
        var windows: [ClosedRange<Int>] = []
        var active = max(0, first - contextLineCount) ... min(
            rows.count - 1,
            first + contextLineCount,
        )
        for index in changed.dropFirst() {
            let candidate = max(0, index - contextLineCount) ... min(
                rows.count - 1,
                index + contextLineCount,
            )
            if candidate.lowerBound <= active.upperBound + 1 {
                active = active.lowerBound ... max(active.upperBound, candidate.upperBound)
            } else {
                windows.append(active)
                active = candidate
            }
        }
        windows.append(active)

        return windows.enumerated().map { hunkIndex, window in
            let selected = Array(rows[window])
            let oldCount = selected.count { $0.oldLine != nil }
            let newCount = selected.count { $0.newLine != nil }
            let oldStart = oldCount == 0
                ? selected[0].oldPositionBefore
                : selected.first(where: { $0.oldLine != nil })?.oldLine ?? 0
            let newStart = newCount == 0
                ? selected[0].newPositionBefore
                : selected.first(where: { $0.newLine != nil })?.newLine ?? 0
            let header = "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
            let lines = selected.enumerated().map { localIndex, row in
                DiffLine(
                    id: DiffLine.ID(rawValue: "\(path):fallback:\(hunkIndex):\(localIndex)"),
                    kind: row.kind,
                    oldLine: row.oldLine,
                    newLine: row.newLine,
                    text: row.text,
                )
            }
            return DiffHunk(
                id: DiffHunk.ID(rawValue: "\(path):fallback:\(hunkIndex)"),
                header: header,
                oldStart: oldStart,
                oldCount: oldCount,
                newStart: newStart,
                newCount: newCount,
                lines: lines,
            )
        }
    }

    private static func lines(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }

    private enum Operation {
        case equal(String)
        case delete(String)
        case insert(String)
    }

    private struct Row {
        let kind: DiffLineKind
        let text: String
        let oldLine: Int?
        let newLine: Int?
        let oldPositionBefore: Int
        let newPositionBefore: Int
    }
}

public enum BoundedMyersDiffError: LocalizedError, Equatable, Sendable {
    case tooLarge(baseBytes: Int, headBytes: Int)
    case tooManyLines(base: Int, head: Int)
    case undecodable
    case workLimitExceeded

    public var errorDescription: String? {
        switch self {
            case let .tooLarge(baseBytes, headBytes):
                "The file is too large for a local diff (\(baseBytes) / \(headBytes) bytes)."
            case let .tooManyLines(base, head):
                "The file has too many lines for a local diff (\(base) / \(head))."
            case .undecodable:
                "The file is binary or not valid UTF-8."
            case .workLimitExceeded:
                "The local diff exceeded its bounded work limit."
        }
    }
}
