# PeriscopeCore – Module Shape

PeriscopeCore owns event processing and persistence. See [README.md](README.md), the [group contract](../AGENTS.md), and the [root contract](../../../AGENTS.md).

## Scope & dependencies

Use Foundation, os, SwiftData, Network, CryptoKit, and JournalKit; Objective-C runtime use is limited to deallocation/target-selector observation, CryptoKit to `ScopeID`.
UIKit requires `#if canImport(UIKit)`. No SwiftUI, app code, or dependencies on PeriscopeUI/Tools.

## Invariants

### Emission and ordering

- Buffer synchronously; drain sinks asynchronously in emission order, with scope definitions first.
- Yield observers under the state lock to preserve racing-emitter order.
- Keep scope IDs deterministic across processes/launches and store-global sequences monotonic across relaunch.
- Sink removal awaits the in-flight drain and flush; no later delivery is owed. Removing a store also uninstalls its journal. Guard: `PeriscopeTests.removalDeliversAndFlushesWhatTheSinkWasOwed`.

### Ambient state

- Distinguish state and occurrence with `AmbientLogEvent.reporting`. Deduplicate repeated network state; retain repeated notification occurrences such as memory warnings.
- Lasting conditions report at `started()` when knowable; app lifecycle deliberately cannot report an initial phase.
- Stamp state at emission. Preserve snapshot identity until a state value changes.
- Level-floor rejection still folds state. Redaction suppression clears that kind instead; neither the suppressed value nor its prior state may leak into later snapshots.
- Custom ambient payloads and accessibility settings stay restricted. Built-in lifecycle, thermal, power, memory, and connectivity events retain explicit baseline approvals.

### Classification and export

- Shareable fields need both `.shareable` declaration and `.shared` emission approval. Classification does not inspect content.
- Baseline sinks consume only `eventName` and `classifiedFields`. Never infer remote data from raw payloads, rendered messages, tags, dynamic scopes, ambient state, external IDs, or attachments.
- Attachment bytes never become remote-export input, including Debug full-metadata export.
- Capture original errors as restricted/errorDetails `LogError` at the logging boundary. Do not copy arbitrary `NSError.userInfo`. Restricted payloads remain eligible for opt-in debug-full export.
- Category values are closed `CaseIterable` members. Revalidate live and persisted projections; optional categories may be null.
- Grants are independent and explicit. Combined UI switches preserve unrelated grants. Context permissions use `LogContextExportRequirements`, independent of UI grouping.
- Requirements compose restrictively: require every control, retain parent restrictions, and preserve `.never`.
- Export through `exportedValue(using:)`; denied fields must not invoke encoders. Structured members use `LogExportable`, not opaque Codable containers or pre-encoded JSON.
- `exportDescription` matches local Codable keys/shape. Persist value-free metadata in rows and journals; filter old rows without it conservatively, never inferring approval from raw payloads.

### Durability and recovery

- Sink failures log to OSLog and increment counts without propagating. Preserve synthetic store-write/drop markers; roll back failed saves so later batches remain usable.
- Append every buffered record to the crash journal before `record()` returns. Stamp sequence under the state lock; perform file I/O outside it. Fault+ uses `F_FULLFSYNC`.
- Journal failures count/log without throwing into emit.
- Ingest before `startSession` and retain journals after failed ingest. Only app processes ingest; extensions journal their sessions without deleting another process's live journal.
- Concurrent live processes sharing one store are unsupported; see [backlog](https://linear.app/kve/view/c0511a6281eb).
- Every on-disk configuration explicitly sets `cloudKitDatabase: .none`.
- Persist versioned JSON (`eventName` + `eventVersion`) without event-payload migrations or typed legacy fallbacks. Historical rows remain raw-readable. Use synthesized Codable; startup never resets the development store automatically.
- Inspector schema/storage/recovery adapters must match the live store and journal locations.

### Spans

- Every began is delivered before its end. `measure` closes every path; watchdogs expire bounded spans and re-begins supersede.
- Relaunch orphan-closes `endsWithProcess`; `survivesRelaunch` resumption remains staged in the backlog.
- Register the begin and its record atomically. Overflow never splits a recorded pair; redaction is transform-only for pair records.
- Decide level floors once at begin. A recorded began gets an end; a floored began silences the pair.
- Relaunch selection uses `SDLogEvent.spanRelaunchPolicy`, not payload decoding. A decode failure may lose the synthetic end's name, not the end; log the failure.

## Testing

`PeriscopeCoreTests` uses `StuffTestHost`, in-memory stores, fresh systems, and injected clocks. Follow the group's explicit `system:` rule.
