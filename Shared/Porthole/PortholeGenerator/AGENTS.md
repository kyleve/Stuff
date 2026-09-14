# PortholeGenerator

This host executable generates Porthole source inventories and compiled calls. Read [README.md](README.md), the [group contract](../AGENTS.md), and the [repository contract](../../../AGENTS.md).

- Keep SwiftSyntax and compiler concerns here. Do not import application modules or the runtime.
- Preserve original source text and conditional compilation in generated output.
- Emit an unsupported reason when type or isolation facts cannot prove a valid call.
- Retain enum constructor results directly; preserve payload labels and assign distinct argument keys.
- Keep non-Sendable enum payloads and results in MainActor boxes without inferring Sendable conformance.
- Inspect enum cases with generated typed switches. Never invoke application encoders, raw-value getters, or computed accessors for classified inspection reads.
- Preserve conditional case patterns and report unsafe payloads as unsupported inspection entries.
- Keep generated calls behind `PORTHOLE_ORIGINAL_SOURCE_CHECK` guards.
- Keep paired application builds in `Tools/porthole_compiler_contract.py`; compare actual compiler settings for every adopting module.
- Preserve the adopting target's compilation mode; `GeneratorCompilerTestSupport` checks private-import linkage and per-source outputs.
- Register each bounded metadata batch synchronously through an isolated registry parameter. Keep async actor hops in the installer dispatch loop; per-registration awaits exhaust compiler memory.
- Reject declaration collisions. Never silently omit a colliding declaration.
- Give repeated syntactic declarations distinct occurrence IDs; preserve private-name collision checks separately.
- Keep source-only control-plane inventories descriptive; exclude named credential files and never emit their source or executable bindings.
- Emit coverage for every declaration, including inactive branches, with final planner reasons. Install it after registration completes; never infer invocation permission from planner support.
- Keep source hashes in coverage and full source only in the source archive. Preserve the Core wire schema through compiler fixtures.
- Embed complete source and coverage regardless of standalone report output. Write a catalog file only for an explicit `--catalog` path.
- Keep paths relative to the package root.
- Test source analysis and emission with Swift Testing in `Tests`.
