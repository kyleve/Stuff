# Patchlight – Product Shape

Patchlight is the iPad/Mac Catalyst GitHub review product described in
[`README.md`](README.md). Read the root [`AGENTS.md`](../AGENTS.md) first.

Dependencies point down `Patchlight` host → `PatchlightUI` → `PatchlightCore`.
Core never imports UI frameworks; UI never opens persistence or constructs a
second account scope; the host selects one production or DEBUG Inspector
runtime at process start and otherwise stays composition-only. Keep one
`PatchlightScope` per signed-in account and inject it down.

Explicit sign-out cancels work and deletes the account vault key before files
or GitHub tokens. Authentication expiry preserves the scope and drafts for
reauthorization. Provider keys are app-global and independently removable.

Area backlog: [`TODOs.md`](TODOs.md). Module tests and deeper invariants live in
each child module's docs.
