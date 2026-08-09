import CryptoKit
import Foundation

/// Builds stable surrounding-context fingerprints and remaps drafts only when
/// one path/rename plus context candidate exists on the new head.
public enum DraftAnchorMapper {
    public enum Resolution: Hashable, Sendable {
        case current(ReviewDraft)
        case remapped(ReviewDraft)
        case ambiguous(candidateCount: Int)
        case deleted
    }

    public struct Result: Identifiable, Hashable, Sendable {
        public var id: UUID {
            draft.id
        }

        public let draft: ReviewDraft
        public let resolution: Resolution

        public init(draft: ReviewDraft, resolution: Resolution) {
            self.draft = draft
            self.resolution = resolution
        }
    }

    public static func fingerprint(
        lineIndex: Int,
        in lines: [DiffLine],
        radius: Int = 2,
    ) -> String {
        precondition(lines.indices.contains(lineIndex), "A fingerprint line index must exist")
        let lower = max(0, lineIndex - radius)
        let upper = min(lines.count - 1, lineIndex + radius)
        let normalized = (lower ... upper).map { index in
            let line = lines[index]
            let marker = index == lineIndex ? ">" : " "
            return "\(marker)\(line.kind.rawValue)|\(line.text.trimmingCharacters(in: .whitespaces))"
        }.joined(separator: "\n")
        return SHA256.hash(data: Data(normalized.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
    }

    public static func map(
        _ drafts: [ReviewDraft],
        from oldHead: GitObjectID,
        to workspace: PullRequestWorkspace,
    ) -> [Result] {
        drafts.map { draft in
            guard let anchor = draft.anchor else {
                return Result(draft: draft, resolution: .current(draft))
            }
            if oldHead == workspace.summary.headOID, anchor.commitOID == workspace.summary.headOID {
                return Result(draft: draft, resolution: .current(draft))
            }

            let files = workspace.files.filter {
                $0.path == anchor.path || $0.previousPath == anchor.path
            }
            guard !files.isEmpty else {
                return Result(draft: draft, resolution: .deleted)
            }

            let candidates = files.flatMap { file in
                candidates(
                    in: file,
                    matching: anchor.contextFingerprint,
                    headOID: workspace.summary.headOID,
                )
            }
            guard candidates.count == 1, let mappedAnchor = candidates.first else {
                return Result(
                    draft: draft,
                    resolution: .ambiguous(candidateCount: candidates.count),
                )
            }
            let remapped = ReviewDraft(
                id: draft.id,
                pullRequest: draft.pullRequest,
                anchor: mappedAnchor,
                body: draft.body,
                updatedAt: draft.updatedAt,
            )
            return Result(draft: draft, resolution: .remapped(remapped))
        }
    }

    private static func candidates(
        in file: DiffFile,
        matching fingerprint: String,
        headOID: GitObjectID,
    ) -> [DiffAnchor] {
        file.hunks.flatMap { hunk in
            hunk.lines.indices.compactMap { index in
                let line = hunk.lines[index]
                guard line.kind != .metadata,
                      self.fingerprint(lineIndex: index, in: hunk.lines) == fingerprint
                else {
                    return nil
                }
                let side: DiffSide = line.kind == .deletion ? .base : .head
                return DiffAnchor(
                    path: file.path,
                    side: side,
                    commitOID: headOID,
                    blobOID: side == .base ? file.baseBlobOID : file.headBlobOID,
                    line: side == .base ? line.oldLine : line.newLine,
                    startLine: nil,
                    contextFingerprint: fingerprint,
                )
            }
        }
    }
}
