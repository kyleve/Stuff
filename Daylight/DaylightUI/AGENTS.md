# DaylightUI

Read [the root contract](../../../AGENTS.md) and [Daylight](../AGENTS.md). See [README.md](README.md) for operation.

SwiftUI presentation, Broadway appearance, and observable models.

Import Core and Mastodon contracts. Keep capture and persistence in services. Route screen actions through DaylightModel.

Use ./test for unit tests. UI snapshots belong to DaylightUISnapshotTests in the shared StuffSnapshotTests scheme. Device camera and Photos checks require the physical iPhone.

Keep live framing independent of archive readiness. Check cancellation after camera permission returns and before starting the preview.

Scope capture-loop state changes and cleanup to the current foreground run and arming revision. Await any camera stop already in flight before starting preview or another run.
