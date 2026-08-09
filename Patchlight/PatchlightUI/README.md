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

Views receive immutable PatchlightCore values and an injected account scope.
They never open SwiftData containers, resolve global credentials, or call raw
provider/GitHub endpoints. Run `./test PatchlightUITests`; image references live
under `SnapshotTests/__Snapshots__` and run through the shared snapshot scheme.
