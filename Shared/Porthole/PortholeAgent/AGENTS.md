# PortholeAgent

Native provider sessions, credentials, and durable tool history. See [README.md](README.md),
the [group contract](../AGENTS.md), and the [repository contract](../../../AGENTS.md).

- Use the pinned Swift AI SDK; keep provider HTTP implementations out of this module.
- Never export this module's credentials or journal APIs through generated debugger bindings.
- Keep keys out of Codable configuration, transcripts, and events.
- Check consent for the selected provider before each model request.
- Persist operation identity before calling the injected policy dispatcher.
- Stop after executor failure; never replay an uncertain operation.
- Keep original context immutable; scope generation decides whether live handles remain usable.
- Keep one journal actor per investigation and write late outcomes to its original file.
- Preserve explicit wire keys when renaming persisted message or operation cases.
- Keep exact large integers as decimal strings at the SDK boundary.
- Test with protocol-conforming providers and temporary journals; do not call live providers from tests.
