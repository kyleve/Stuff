# PatchlightUI

PatchlightUI is Patchlight's presentation and lifecycle layer. It owns the
Broadway-styled SwiftUI app surfaces, UIKit bridges, lifecycle composition,
Flyover/preview fixtures, SnapshotKit matrices, and DEBUG Inspector/Periscope
tooling.

The current root establishes an iPad/Catalyst `NavigationSplitView` with Review
Requested, My Open PRs, and Repositories destinations and a localized GitHub
onboarding entry. The snapshot matrix intentionally uses an iPad viewport; the
shipping product has no iPhone destination in v1.

Views receive immutable PatchlightCore values and an injected account scope.
They never open SwiftData containers, resolve global credentials, or call raw
provider/GitHub endpoints. Run `./test PatchlightUITests`; image references live
under `SnapshotTests/__Snapshots__` and run through the shared snapshot scheme.
