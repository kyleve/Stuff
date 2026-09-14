# PortholeRuntime

The shared execution boundary is described in [README.md](README.md). Read the
repository [contract](../../../AGENTS.md) and Porthole group contract.

- Depend on PortholeCore and system frameworks only. Use CryptoKit for content hashes and Darwin for descriptor-confined files.
- Revalidate scope identity after every suspended operation.
- Revalidate the activation generation after asynchronous preparation and before result delivery.
- Bind approval to the entire invocation and consume it before execution.
- Persist a start receipt before side effects. Never replay uncertain operations.
- Keep read receipts bounded and in memory; never turn subscriptions into durable operation history.
- Keep observations scoped to their original activation and native owner; use the shared executor for every read sample.
- Keep one bounded latest sample per observation. Stop workers and reads on disable, scope invalidation, and owner teardown.
- Preserve stopped observation IDs and closed owners until their scope boundaries end; never revive a delayed start.
- Store Sendable values only. Generated code owns executor hops.
- Keep explicit service roots scope-owned and opaque results in bounded pools. Lease native arguments and results through delivery; never evict a leased reference.
- Reuse child handles only for immutable parent fields. Expire all children when their parent is released or evicted.
- Box non-Sendable MainActor values in `PortholeMainActorValue`; never unwrap them off MainActor or erase the box's concrete generic type.
- Keep complete source coverage separate from registrations. Resolve availability from installed descriptors and handlers; coverage never grants invocation access.
- Install coverage after module registration. Validate its source hashes and identities atomically; release it with its owning scope.
- Keep coverage queries and aggregate retention bounded. Preserve inactive and policy-excluded declarations with their reasons.
- Test approval reuse, cancellation races, stale scopes, and journal recovery.
