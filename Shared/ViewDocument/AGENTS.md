# ViewDocument

ViewDocument renders a finite, read-only document vocabulary. See [README.md](README.md) and the repository [rules](../../AGENTS.md).

- Keep Core Foundation-only. Keep UI dependent only on Core and system frameworks.
- Never import Broadway, Where, or SnapshotKit into production targets.
- Validate before rendering. Keep validated documents immutable and reject missing assets before view construction.
- Keep modifier order stable. Host registries own images and approved symbols; the renderer never resolves URLs or file paths.
- Inject appearance, activity, and static-motion policy. Do not create animation tasks that outlive the view.
- Keep field and case names stable within a schema version. Reject unsupported schema versions.

Run `./test ViewDocumentCoreTests` and `./test ViewDocumentUITests` for unit coverage.
