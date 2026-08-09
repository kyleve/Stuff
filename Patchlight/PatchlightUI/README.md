# PatchlightUI

PatchlightUI is Patchlight's presentation and lifecycle layer. It owns the
Broadway-styled SwiftUI app surfaces, UIKit bridges, lifecycle composition,
Flyover/preview fixtures, SnapshotKit matrices, and DEBUG Inspector/Periscope
tooling.

The root provides the complete GitHub device-flow experience and an
iPad/Catalyst `NavigationSplitView` with Review Requested, My Open PRs, and
installation-grouped searchable Repositories destinations. A dedicated PR
workspace presents Overview, Conversation, Snapshots, and changed files. Text
patches render through a viewport-lazy `UICollectionView` bridge with reusable
TextKit cells and adaptive unified/split modes; unavailable binary, oversized,
or undecodable content stays explicit and links to GitHub.

Reads refresh on launch, foreground, manual action, and every five minutes only
while the dashboard is visible. Cached content carries its refresh time and
failure reason instead of masquerading as live data. The snapshot matrix uses
an iPad viewport; the shipping product has no iPhone destination in v1.

The review loop renders issue discussion, reviews, checks, inline/outdated/
resolved threads, and replies. Selecting a diff line creates an encrypted local
draft; Submit Review batches those drafts with Comment, Approve, or Request
Changes, while replies and conversation/file comments remain visibly immediate.
Patchlight refreshes the head before submission and freezes stale anchors into
unique-remap, re-anchor, file-level, or discard choices. Reaching a rendered
file footer marks it viewed by default, with an explicit-only preference.

The workspace exposes the five labeled Critical–Everything depths through a
snapped accessible slider and keyboard commands. Fully hidden files remain in a
collapsed Hidden Changes group, hidden hunks retain expandable placeholders,
and increasing depth marks newly revealed work unread without silently
unviewing the GitHub file. File menus provide per-head Always Show/Mechanical
corrections and manual PNG routing.

Snapshots use a virtualized path-grouped gallery plus a focused checkerboard
canvas. Base/head, side-by-side, wipe, opacity overlay, heatmap, Fit, and 100%
modes share zoom/pan; dimension mismatches disable invalid modes with an honest
explanation. Dragging on a base or head image opens a tagged annotation composer
that sends an interoperable visible file-level comment.

AI remains an optional layer over that complete GitHub workflow. Onboarding and
Settings store OpenAI/Anthropic keys in app-global Keychain items, select a
versioned preset or explicit advanced model ID, and require both global and
per-repository opt-in. Analysis starts only from an explicit Run Analysis
button; its summary, findings, partial-hunk state, provider/model, token usage,
bounded context metrics, duration, and request ID remain visible. Findings can
seed editable local drafts but never publish automatically. Snapshot image
analysis has a separate off-by-default consent and receives only the selected
base/head pair plus local pixel metrics.

Views receive immutable PatchlightCore values and an injected account scope.
They never open SwiftData containers, resolve global credentials, or call raw
provider/GitHub endpoints. Run `./test PatchlightUITests`; image references live
under `SnapshotTests/__Snapshots__` and run through the shared snapshot scheme.
