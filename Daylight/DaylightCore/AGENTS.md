# DaylightCore

Read [the root contract](../../../AGENTS.md) and [Daylight](../AGENTS.md). See [README.md](README.md) for API and behavior.

Keep domain and service code independent of UI, Where, and Ledger. Create collaborators once in the app root and inject them. Persist transitions before external side effects. Keep staged images until all consumers finish. Use 1:1 Swift Testing files and injected protocol implementations.

Preserve pre-RAW capture records with absent format and delivery checkpoints. Keep saved Photos identifiers intact; see CapturedImageTests and ManualCaptureServiceTests.

Persist highlight deliveries before marking selection complete. Cleanup must not observe a selected image whose deliveries are still being registered.
