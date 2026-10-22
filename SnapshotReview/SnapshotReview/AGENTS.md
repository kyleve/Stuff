# SnapshotReview — Module Shape

Thin Catalyst app host. See [README.md](README.md). Read the [group](../AGENTS.md) and [repository](../../AGENTS.md) contracts first.

- Create the store and model only at the app root.
- Keep browser and file behavior in the sibling library modules.
- Use `./ide --no-open` and `mise exec -- tuist build SnapshotReview` to build.
- Unit and image coverage live in the sibling modules.
