# PortholeCore

PortholeCore defines the values, capabilities, contexts, and requests shared by
all Porthole clients. It uses Foundation and CryptoKit for source hashes. Values have a JSON wire
representation; native objects use scoped references instead of pointer values.

Integer values preserve the full Int64 and UInt64 ranges, including fields nested in Codable objects.
Decoding uses the signed case when a value fits Int64 and the unsigned case for larger positive integers.
Numeric equality compares exact mathematical values across signed, unsigned, and floating representations.
It never converts a large integer to Double to compare it.
Whole Double values encode as exact integer tokens, so exponent formatting cannot change their persisted value.

Fractional numbers use finite Double values. Integral JSON values outside Int64 through UInt64 are rejected instead of rounded.
This also rejects ambiguous large floating values such as `1e100` and `-1e100`.
Encoding applies the same range check before a result can enter a persisted journal.

`PortholeCapability` describes parameters, results, effects, execution ownership, and availability.
`PortholeExecutionOwnership` identifies unisolated, MainActor, actor-instance, or adapter-managed execution.
`PortholeInvocation` binds an operation identity to an exact scope generation.
`PortholeExecuting` is the common discovery and invocation interface.

`PortholeObservationClient` provides typed start, read, and stop calls over ordinary invocation.
The same methods are available on `PortholeExecuting`. A frozen execution closure can use the client directly.
Choose the observation ID before starting. Stop can then prevent a delayed start, even if its reply was lost.

Observations retain their latest sample. Long-poll reads return a newer sequence or the current state at their deadline.
Sequence gaps identify skipped samples; they do not provide historical evidence.
Native transports propagate `PortholeObservationOwnership.current` and call `PortholeObservationOwning` during teardown.
Adapters that cross detached tasks or C callbacks must propagate the supplied owner when they invoke nested APIs.

`PortholeCoverageDocument` identifies every inventoried declaration by module, build, compiler conditions, and source hash.
Planner availability describes generated support; `PortholeCoverageState` describes the actual installed result.
Inactive declarations retain their planned support and conditions. Source-only and excluded-file origins stay explicit.
An inspectable-source entry exposes declaration evidence without promising live value inspection or invocation.
The document contains no source bodies. The source archive supplies verified text through the existing evidence tools.
The version-one declaration kind includes `enumerationInspection` for generated enum reads, separately from `enumerationCase` constructors.
Existing declaration kinds and fields retain their wire names. Older clients that cannot decode the new kind must update before reading these coverage pages.

`PortholeCoverageClient` reads bounded module and declaration pages through ordinary capability invocation.
Each page carries its scope generation. The client rejects replaced scopes and malformed pagination metadata.
Modules with no active declarations still appear. Counts link to declaration pages; they do not replace those entries.
