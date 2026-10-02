# IdentityKit – Module Shape

IdentityKit owns UUID identities scoped to a phantom domain owner.
See [README.md](README.md) for usage and the wire contract.
Read the [repository rules](../../AGENTS.md) first.

- Depend only on Foundation. Keep domain and persistence behavior in consumers.
- Preserve the bare UUID wire shape. Never encode the owner name.
- Do not require protocols on the owner. Only the stored UUID crosses isolation boundaries.
- Use UUID ordering only for deterministic ties, never to infer creation time.

Swift Testing lives in `Tests/` and runs through `./test IdentityKitTests`.
`TypedIDTests` guards wire compatibility and unconstrained-owner concurrency.
