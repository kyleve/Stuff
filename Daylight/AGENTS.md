# Daylight

Read [the repository contract](../AGENTS.md). [README.md](README.md) owns setup and operation.

Keep the app composition root above DaylightUI, DaylightMastodon, and DaylightCore. Core never imports UI or destination modules. Register publishing adapters at the root; never switch over destination names in capture code.

Keep each RAW/JPEG pair in one Photos asset. Expose both originals to adapters until their dependent work finishes. Do not add photographic edits.

Freeze capture settings per sequence. Persist image bytes before Photos or network side effects. Preserve ambiguous outcomes for review instead of blindly duplicating assets or posts. Never remove Photos assets. Exact location and credentials never enter social image metadata or logs.

Run unit suites through ./test and UI snapshots through StuffSnapshotTests. Camera, Photos saving, and unattended thermal behavior require physical-device acceptance.
