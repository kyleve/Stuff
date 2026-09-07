# Daylight

Read [the root contract](../../../AGENTS.md) and [Daylight](../AGENTS.md). See [README.md](README.md) for operation.

The application composition root and bundled attribution.

Create the camera, archive, logging system, and destination once. Inject the same instances into every consumer. Keep screen implementations in DaylightUI.

Use ./test for unit tests. UI snapshots belong to DaylightUISnapshotTests in the shared StuffSnapshotTests scheme. Device camera and Photos checks require the physical iPhone.

Keep publishing configuration failure isolated from capture startup. Surface adapter issues through its configuration contract.
