# StuffCore – Module Shape

Small cross-app foundations — Foundation and system frameworks only, with no
app or feature-module imports. See [`README.md`](README.md).

`CredentialStore` remains binary and app-agnostic; an app chooses its service,
typed keys, text encoding, and deletion semantics at its own boundary.

Complements root [`AGENTS.md`](../../AGENTS.md). Tests: `StuffCoreTests` in
`StuffTestHost` (`./test StuffCoreTests`).
