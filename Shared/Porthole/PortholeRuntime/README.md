# PortholeRuntime

Create a `PortholeRegistry` at the application composition root. Add scopes and
register descriptors and handlers while disabled. Call `setEnabled(true)` only
after activation. Use `PortholeExecuting` for every local or remote invocation.

Operations with unknown or mutating effects produce a `PortholeActionProposal`.
The trusted presentation layer calls `approve` with the exact proposal before
retrying that operation. A changed request cannot reuse approval.

Objects must be Sendable; actor-isolated references remain on their declared
executors. Scope invalidation cancels work and releases objects. Results from
an invalidated scope are rejected even when native code ignores cancellation.
Disabling the registry also rejects pending results after reactivation, including
requests waiting for journal lookup before native work starts.
Completed mutations keep their successful receipt even when delivery is cancelled.

`PortholeMainActorValue` carries MainActor-owned protocol values whose existential
type is not Sendable. The registry retains the box and reports the original value
type in its handle. Generated adapters create and unwrap it only on MainActor.
Resolution and decoding take the box's Sendable metatype. Non-Sendable existential
metatypes do not cross the registry's actor boundary.

Explicit `retain(_:in:)` calls create scope-owned roots. Opaque call results use the bounded `PortholeObjectRetention.results` pool.
Hosts can select a smaller named pool through `retain(_:in:retention:)` or `encode(_:in:retention:)`.
The registry evicts the least recently used inactive handles when a pool or total capacity is full.
Eviction expires inspection references without changing live application state. Expired identifiers never bind to replacement objects.
Native arguments, resolved handles, and new results remain leased until the operation finishes delivery.
When every possible victim is leased or scope-owned, allocation fails clearly instead of evicting an active argument.

`encodeChild(_:key:of:in:)` reuses a named field of an immutable captured parent.
The caller must keep that key's meaning and value unchanged for the parent's lifetime.
Releasing or evicting the parent expires its children. The release operation rejects handles used by ongoing native work.
Clients can invoke `porthole.objects.release` with the reference's `objectID` and `typeName` in its original scope.
This isolated operation changes debugger retention only and uses the normal operation receipt path.

Unknown, mutating, and isolated operations write a durable receipt before execution.
A process interruption leaves unfinished work uncertain. Reusing its identity never executes it twice.
Reads use a memory cache capped at 256 receipts and eight MiB of encoded data.
They do not write the operation journal. Oversized results are returned without retention.
Scope invalidation and disabling the registry clear cached reads; late results do not repopulate them.
Recent read retries return their cached result. An evicted read can execute again and observe newer state.
Durable receipts take precedence over the read cache. Agent investigations keep their own durable result history and never automatically replay an uncertain operation.
Saved results can contain expired object references. Restoring a receipt keeps those original identifiers; it never repeats completed mutations to refresh them.

`PortholeBuiltinCapabilities.install` includes observation start, read, and stop controls.
Every client uses these controls through `PortholeObservationClient` or `PortholeExecuting`.
Only callable capabilities classified as reads can run repeatedly. Each sample uses the ordinary executor with a fresh invocation ID.
The registry leases receiver and argument handles until the observation stops or fails.

Each observation retains one latest sample, limited to one MiB. Failures preserve the last good sample and stop sampling.
At most 32 observations and 64 pending reads can exist. Sampling intervals range from 1000 through 60000 milliseconds.
A read can wait up to 10000 milliseconds. Its timeout returns the current snapshot.
Consumers compare sequence numbers and must not describe skipped samples as recorded history.

Stop prevents a delayed start with the same ID. Stopped IDs remain reserved while their scope exists, including across disable and reactivation.
An identical live request reuses its observation even when a script or agent supplies another outer operation ID.
Changed requests cannot reuse an observation ID.
The ID ledger holds at most 4096 entries; replacing their application scope releases them.
Disabling the registry, invalidating a scope, and closing a native observation owner cancel its workers and waiting reads.
Late samples cannot update an ended observation. Cancellation requests native cancellation without promising rollback or forced termination.

Remote sessions supply the native task-local observation owner. Nested calls inherit it.
The registry checks ownership before returning cached control results, as well as during live operations.
Native calls without an owner can manage observations from the phone.
Closed owner IDs remain reserved until all application scopes end. After 4096 closed owners, further owned starts fail closed until then.
Adapters that use detached tasks or C callbacks must propagate their supplied owner when they invoke nested APIs.

Source search and read results include the installed file SHA-256 and original scope token.
Consumers can resolve a selected line without substituting source from a later scope or build.

`PortholeFiles` exposes only host-injected roots. File operations open directory
components relative to retained descriptors and reject symbolic links. Directory
pages contain at most 200 entries; enumeration stops with an explicit error above
10,000 entries. Reads and writes enforce the host's byte limit.

An approved write requires the hash observed before editing. New-file writes
cannot replace an existing file. Existing-file replacement checks the current
hash immediately before atomic rename. It cannot lock out another subsystem
that writes the file without participating in that check. Use a subsystem adapter
for application databases and other files with coordinated writers.

Complete declaration coverage is separate from executable registrations.
Generated modules call `installCoverage(_:in:)` after source installation and compiled registration.
Installation validates source hashes and descriptor identities before it changes coverage state.
Repeated identical installation succeeds; conflicting metadata fails without partial changes.
Queries fail explicitly before coverage is installed in their scope. An explicitly installed empty document remains a valid empty result.

`porthole.coverage.modules` lists every installed module, including modules with no active declarations.
`porthole.coverage` accepts a typed `PortholeCoverageQuery` and returns source locations, hashes, and the original scope.
Search includes signatures, compiler conditions, paths, and both planner and runtime reasons.
Both capabilities are classified reads and use the ordinary execution boundary.
Pages contain at most 200 rows. Search accepts at most 4096 UTF-8 bytes.

Coverage state uses the installed descriptor and handler. A planned callable declaration can be inactive in this build.
An installed callable descriptor without a handler provides source inspection only.
Source-only and excluded rows retain their explicit policy reasons; coverage cannot create executable handlers.
Unknown effects still require approval when a callable row is invoked.

The registry limits total retained coverage to 256 modules, 100,000 declarations, and 64 MiB of encoded module metadata.
Each incoming document also has a 64 MiB limit. Scope invalidation releases its coverage and capacity.
Disabling the registry blocks coverage reads while preserving prepared metadata for reactivation.
