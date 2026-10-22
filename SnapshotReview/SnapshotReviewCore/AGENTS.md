# SnapshotReviewCore — Module Shape

File formats, discovery, and review persistence. See [README.md](README.md). Read the [group](../AGENTS.md) and [repository](../../AGENTS.md) contracts first.

- Validate suite-relative paths on construction and decoding.
- Persist explicit versioned formats with stable raw enum values.
- Compare exact prior review bytes inside file coordination before atomic replacement.
- Run file discovery, image inspection, and hashing away from the main actor.
- Guard content identity again before review writes.
- Run `./test SnapshotReviewCoreTests` after core changes.
