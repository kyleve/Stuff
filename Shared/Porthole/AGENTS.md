# Porthole

Porthole is the reusable application debugger described in [README.md](README.md).
Read the repository [contract](../../AGENTS.md) and the owning module contract.

- Keep the core and runtime independent of UI, providers, and application code.
- Route every client through the same runtime approval and scope boundary.
- Inject existing application resources. Never reopen a live application store.
- Keep credentials opaque to source export, scripts, and diagnostic capabilities.
- Preserve executor ownership. Never make arbitrary objects unchecked Sendable.
- Report unsupported bindings explicitly. A catalog entry does not imply invocation support.
- Treat cancellation as a request, not rollback of an operation already started.
- Reuse source and test directories in the local runtime package; keep its dependency pins aligned with the application graph.
