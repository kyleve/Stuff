# Swift conventions

Module instructions add local contracts to these repository conventions.

## Conventions

### Testing

- Use Swift Testing (`import Testing`) for unit tests.
- Add tests for distinct behavior, compatibility contracts, or demonstrated regressions. Prefer assertions that distinguish a meaningful failure.
- Do not add tests solely for synthesized equality, hashing, or ordinary stored-property mutation. Preserve custom behavior and persisted or wire-format identity checks.
- Do not copy authored stylesheet constants into assertions. Follow [Broadway coverage guidance](../skills/building-ui/references/broadway.md) for styling tests.
- Host views to verify behavior that needs the mounted hierarchy. A view-exists assertion adds no useful coverage to a snapshot-covered surface.
- Name test files after the behavior or source they cover, such as `FooTests.swift`. A source file does not require a test file. Keep shared fixtures in support files.
- Apply this coverage policy before generic skill advice about generating tests for every function or avoiding all hosted view tests.
- Await observable conditions instead of fixed delays. For races, hold the dependency at its suspension point, apply the competing operation, then release it.
  Assert final state and side effects, including cancelled or superseded completions when an operation can restart.
- Put test/preview-only hooks behind `@_spi(Testing)`, with `#if DEBUG` when release must exclude them. Use the corresponding SPI import.
  Inject small test limits through those hooks or test factories, not production parameters.
- Test doubles and production implementations conform to the same protocol. Do not add fake-behavior enum branches to production types.
- Consider seeded, replayable adversarial tests for state machines with many branches.

### Types, state, and API design

- Shorthand type aliases preserve the final component: `typealias Episode = FlightGroundInference.Episode`. Keep the qualified name when it conflicts locally.
- Use named structs for multi-field values that escape a function. Tuples are limited to ad-hoc local returns, not properties, collection elements, or public API.
- Keep data structs as values with independent state across copies. A `let` property can still point every copy at the same mutable object, even through an optional or collection.
  Store shared mutable objects, such as `@Observable` models, in the component that owns their lifetime. If the value needs to identify that state, carry a typed ID for the entity or occurrence it represents.
- Group large flat types into nested values and focused child types.
- Keep identities `Hashable` and domain-specific, including UUID identities. Prefer concrete types or generics; use `AnyHashable` only at heterogeneous or nongeneric boundaries.
  Never use raw strings as identity types.
- Carry the strongest existing domain type through API/helper boundaries. Unwrap it only at persistence, wire, or system boundaries.
  If a raw scalar is unavoidable, label its role (`sampleID`, not `id`).
- Create identity when creating its entity. Represent unavailable persisted/system identity explicitly; never invent a fallback UUID.
- Core/store APIs require explicit arguments. Defaults are limited to SwiftUI convenience initializers or zero values whose omission cannot change semantics.
  An empty collection that suppresses evidence is not such a default.
- For `Equatable` stored values, guard `oldValue != newValue` before `didSet` side effects.
- Enumerate every case in enum switches. Use `@unknown default` only for non-frozen external enums.
- Document non-obvious types and algorithm decisions. Name heuristic thresholds and document their units and decision meaning beside the owning policy.

### Errors and failure

- Carry the original `Error` through services and observable failure state. Derive display text at the UI boundary.
- Core APIs expose failure through `throws`, `Result`, or a typed error. Do not hide failures with `try?`, empty catches, or success-shaped defaults.
- A handling catch logs through the module's structured logging API and preserves honest state: retain the last good value or expose failure.
  Degraded but handled recovery is a warning. Callers can rethrow or choose the recovery policy.
- Recoverable/user failures must surface and log. For impossible or misconfigured states, use `precondition`/`assertionFailure` in debug and a minimal safe release fallback.

### Persistence and wire formats

- Prefer synthesized `Codable`. Document a custom conformance's reason on the conformance itself.
  The supported exceptions are a single-value wire shape and a composite identity using Where's `WhereStoreURLCodable`/`StoreURL`, never joined `type:value` strings.
- Persisted formats must survive Swift-side renames. Associated-value enum synthesis persists case names.
  Do not add custom keyed decoding merely to fill missing fields from an older shape; obey the owning module's migration policy.
- Persist coupled preferences as one encoded domain value. State missing and invalid-value policies at the owning preference.

### UI construction

Use SFSafeSymbols' `SFSymbol` and `systemSymbol` overloads. Do not use raw strings or unchecked symbol construction.
Run `./sf-symbols --lint`. `WhereShortcuts.swift` is the sole exception: its App Shortcuts metadata macro requires compile-time string literals.

### Modeling state

Represent dependent values with one enum or named value. Avoid independent loading/error/data flags, parallel indexed collections, and kind tags beside case-specific optionals.
Use `Optional` or a dedicated case for absence instead of sentinel values. If only some enum cases are accepted, use a smaller type and convert explicitly.

### Composition: create once, inject down

- Create each shared resource once at its composition root, when needed, and inject it. Do not re-resolve globals or add static get-or-create registries.
- Select an alternate boot stack through one class-bound runtime at process initialization. Do not spread launch-mode checks through app code.
- Platform-created consumers use the platform's DI seam as a handoff. Early consumers await installation with cancellation support; the seam never creates the resource.
- Derived stacks reuse their base's resources and computed dependencies. Derivation stays synchronous and nonthrowing.
- Re-fire composition hooks whenever the lifecycle recreates their resource, so consumers receive the current session.
