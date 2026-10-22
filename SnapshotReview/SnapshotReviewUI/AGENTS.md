# SnapshotReviewUI — Module Shape

SwiftUI browsing and UIKit image zoom for Snapshot Review. See [README.md](README.md). Read the [group](../AGENTS.md) and [repository](../../AGENTS.md) contracts first.

- Use the injected store and one main-actor observable model.
- Preserve image identity and normalized points when changing scale.
- Do not silently substitute another device or appearance for a missing counterpart.
- Keep authored tokens in ReviewStylesheet; system semantic appearance stays native.
- This developer-only tool intentionally uses English literal UI labels and metadata labels. Localization is not part of its public contract.
- Record snapshot matrices beside their views and use synchronous fixtures without filesystem access.
- Run `./test SnapshotReviewUITests` and the UI snapshot suite after visual changes.
