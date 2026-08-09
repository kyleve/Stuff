import Foundation

public struct ReviewAnalysisChunkPlan: Sendable {
    public let requests: [ReviewAnalysisRequest]
    public let omittedHunkIDs: Set<DiffHunk.ID>

    public init(
        requests: [ReviewAnalysisRequest],
        omittedHunkIDs: Set<DiffHunk.ID>,
    ) {
        self.requests = requests
        self.omittedHunkIDs = omittedHunkIDs
    }
}

/// Produces hunk-aligned requests in deterministic risk order. No partial hunk
/// is ever sent when a preset's byte budget is exhausted.
public enum ReviewAnalysisChunker {
    public static func plan(
        workspace: PullRequestWorkspace,
        reviewPlan: DeterministicReviewPlan,
        budget: AnalysisBudget,
    ) -> ReviewAnalysisChunkPlan {
        let candidates = reviewPlan.files
            .flatMap { filePlan in
                filePlan.hunks.map {
                    Candidate(
                        file: filePlan.file,
                        hunk: $0.hunk,
                        depth: $0.assessment.minimumDepth,
                        hardSafety: $0.isHardSafetySignal,
                    )
                }
            }
            .sorted {
                if $0.hardSafety != $1.hardSafety { return $0.hardSafety }
                if $0.depth != $1.depth { return $0.depth < $1.depth }
                if $0.file.path != $1.file.path { return $0.file.path < $1.file.path }
                return $0.hunk.id.rawValue < $1.hunk.id.rawValue
            }

        let targetChunkBytes = max(
            64 * 1024,
            min(512 * 1024, budget.diffBytes / budget.maximumProviderCalls),
        )
        var selected: [Candidate] = []
        var omitted = Set<DiffHunk.ID>()
        var selectedBytes = 0
        for candidate in candidates {
            let bytes = AnalysisDiffRenderer.render(candidate.file, hunk: candidate.hunk)
                .utf8.count
            guard selectedBytes + bytes <= budget.diffBytes else {
                omitted.insert(candidate.hunk.id)
                continue
            }
            selected.append(candidate)
            selectedBytes += bytes
        }

        var groups: [[Candidate]] = []
        var current: [Candidate] = []
        var currentBytes = 0
        for candidate in selected {
            let bytes = AnalysisDiffRenderer.render(candidate.file, hunk: candidate.hunk)
                .utf8.count
            if !current.isEmpty, currentBytes + bytes > targetChunkBytes {
                groups.append(current)
                current = []
                currentBytes = 0
            }
            if groups.count >= budget.maximumProviderCalls {
                omitted.insert(candidate.hunk.id)
            } else {
                current.append(candidate)
                currentBytes += bytes
            }
        }
        if !current.isEmpty, groups.count < budget.maximumProviderCalls {
            groups.append(current)
        } else {
            omitted.formUnion(current.map(\.hunk.id))
        }

        let requests = groups.map { candidates in
            ReviewAnalysisRequest(
                pullRequest: workspace.summary.id,
                baseOID: workspace.baseOID,
                headOID: workspace.summary.headOID,
                files: files(from: candidates),
            )
        }
        return ReviewAnalysisChunkPlan(requests: requests, omittedHunkIDs: omitted)
    }

    private static func files(from candidates: [Candidate]) -> [DiffFile] {
        var orderedPaths: [String] = []
        var sourceByPath: [String: DiffFile] = [:]
        var hunksByPath: [String: [DiffHunk]] = [:]
        for candidate in candidates {
            if sourceByPath[candidate.file.path] == nil {
                orderedPaths.append(candidate.file.path)
                sourceByPath[candidate.file.path] = candidate.file
            }
            hunksByPath[candidate.file.path, default: []].append(candidate.hunk)
        }
        return orderedPaths.compactMap { path in
            guard let source = sourceByPath[path] else { return nil }
            return DiffFile(
                path: source.path,
                previousPath: source.previousPath,
                status: source.status,
                additions: source.additions,
                deletions: source.deletions,
                baseBlobOID: source.baseBlobOID,
                headBlobOID: source.headBlobOID,
                availability: source.availability,
                hunks: hunksByPath[path] ?? [],
            )
        }
    }

    private struct Candidate {
        let file: DiffFile
        let hunk: DiffHunk
        let depth: ReviewDepth
        let hardSafety: Bool
    }
}

public enum AnalysisDiffRenderer {
    public static func render(_ request: ReviewAnalysisRequest) -> String {
        request.files.map { file in
            file.hunks.map { render(file, hunk: $0) }.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    static func render(_ file: DiffFile, hunk: DiffHunk) -> String {
        let lines = hunk.lines.map { line in
            let prefix = switch line.kind {
                case .addition: "+"
                case .deletion: "-"
                case .context: " "
                case .metadata: "!"
            }
            return "\(prefix)\(line.text)"
        }.joined(separator: "\n")
        let payload = "\(hunk.header)\n\(lines)"
        let metadata: String
        do {
            let data = try JSONEncoder.analysisDiff.encode(Metadata(
                path: file.path,
                hunkID: hunk.id.rawValue,
            ))
            guard let value = String(data: data, encoding: .utf8) else {
                preconditionFailure("JSON metadata must be valid UTF-8.")
            }
            metadata = value
        } catch {
            preconditionFailure("Diff metadata must remain encodable: \(error)")
        }
        return """
        PATCHLIGHT_UNTRUSTED_DIFF
        metadata_json=\(metadata)
        payload_utf8_byte_count=\(payload.utf8.count)
        payload_follows
        \(payload)
        PATCHLIGHT_UNTRUSTED_DIFF_END
        """
    }

    private struct Metadata: Codable {
        let path: String
        let hunkID: String

        enum CodingKeys: String, CodingKey {
            case path
            case hunkID = "hunk_id"
        }
    }
}

extension JSONEncoder {
    fileprivate static var analysisDiff: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
