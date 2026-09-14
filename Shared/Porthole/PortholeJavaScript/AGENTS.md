# PortholeJavaScript

The bounded console bridges QuickJS to shared native tools. See [README.md](README.md)
and the repository [contract](../../../AGENTS.md).

- Import PortholeCore and CQuickJS; keep provider credentials and UI outside this module.
- Keep every QuickJS value on its owning serial queue.
- Pass only immutable values across the native mailbox.
- Route native calls through the injected policy dispatcher.
- Preserve Int64 and UInt64 through BigInt; never round native identifiers through Double.
- Keep each command's VM and native tasks within one cancellation lifetime.
- Test interpreter behavior and cancellation with Swift Testing in Tests.
