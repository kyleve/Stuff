# Swift conventions

## Conventions

Global rules for all Swift in this repo. A module's own `AGENTS.md` layers its
scope and invariants on top rather than restating these.

### Testing

- **Swift Testing** (`import Testing`) for all unit tests – do not use XCTest.
- **Test files are 1:1 with implementation files.** A type in `Foo.swift` is
  tested in `FooTests.swift`. When a source file is split (e.g. one detector per
  file), split its tests to match. Do not keep one omnibus file. Shared
  fixtures/helpers live in their own support file (e.g.
  `WhereCoreTestSupport.swift`, `DataIssueDetectorTestSupport.swift`). Do not bundle them
  into a test file. That way a single test clock or input builder is not copy-pasted
  across suites.
- **Wait for conditions, not timing.** Prefer polling a predicate (`waitUntil`,
  `waitFor`, `waitForResolution`) over fixed run-loop counts or `sleep`. Fixed
  delays flake under load.
- **Control race tests at the suspension boundary.** Hold the dependency there.
  Apply the competing operation. Then release the held call.
  Assert the final state and side effects. If the operation can restart,
  cover cancelled or superseded completions.
- **Test-only API is `@_spi(Testing)`, not a production parameter.** Hooks that
  exist for tests or previews — direct store mutation, failure injection, queue
  introspection, a capacity or clock override — are marked `@_spi(Testing)`, in
  `#if DEBUG` when release must not ship them, and imported as
  `@_spi(Testing) import <Module>`. Tests inject small values (a retry-queue
  size of 20) rather than hardcoding the production limit.
- **Test doubles conform to the production protocol.** Model a seam as a
  protocol the real and fake both conform to (`LocationSource` /
  `ScriptedLocationSource`). Never use an enum switch inside a production type
  that branches to fake behavior.
- State machines with many branches (launch runners, lifecycle drives) benefit
  from **seeded fuzz/adversarial tests** that replay failures exactly.

### Types, state, and API design

- **Preserve the nested type name in shorthand aliases.** When shortening a
  qualified type, use its final component: `typealias Episode = FlightGroundInference.Episode`.
  Use `Trajectory` for `GPSCorrectionPolicy.Trajectory`.
  If that name conflicts in the current scope, keep the qualified type name.
- Prefer small named structs over tuples for any value with more than
  one field or that escapes a single function. Tuples are fine as
  ad-hoc inline returns. They must not appear in property types,
  collection element types, or public API.
- **Group large flat types into sub-structs and child types.** When a type
  grows a long flat property list (e.g. a config with a cluster of watchdog
  knobs) or a file accretes several behavioral areas, group related properties
  into nested structs and split responsibilities into focused child types.
  Do not let one god-type keep growing.
- Identifiers/keys are `Hashable`. Use a typed enum, or a dedicated struct when
  the identity has structure (Where's `StoreURL` composite keys), or
  `AnyHashable`. Give UUID identities a domain-specific type too, such as
  `SampleAttributionRevision.ID`. Distinct identities must remain distinct
  types even when both store a UUID. Never use raw `String`s. A typed token can't silently typo into
  a new, untracked id. Prefer carrying the *concrete* type where a generic
  can (`LaunchPlan` is generic over its step `ID`). Reach for `AnyHashable`
  only where a generic can't reach (a non-generic environment value, a
  heterogeneous container). Examples: `LaunchStepID`,
  `WherePreferences.Keys`, `StoreURL`.
- **Keep domain values typed through API and helper boundaries.** Accept the
  strongest existing domain type (`Region`, `CalendarDay`, a nested `ID`). Unwrap its `rawValue` / storage key only at the persistence, wire, or system
  boundary that requires the primitive. When no domain type exists and a raw
  scalar is unavoidable, give it a role-specific label (`sampleID`,
  `evidenceID`). Never use an ambiguous `id`.
- **Create identity only when creating the entity.** Do not generate a UUID as
  a fallback for an unavailable persisted or system identity. Represent that
  unavailable state explicitly.
- **Avoid parameter defaults on Core/store APIs.** Prefer explicit call-site
  arguments so new behavior is not silently opted into. Reserve defaults for
  SwiftUI convenience inits and obvious zero values (`[]`, `.zero`) where
  omission can't change semantics. An empty collection is not a harmless
  default when it suppresses evidence or domain behavior.
  Test overrides use `@_spi(Testing)` hooks or
  dedicated test factories. Do not use production parameter defaults.
- **`didSet` must skip work when the value is unchanged.** When the stored
  type is `Equatable`, guard `oldValue != newValue` before invalidation,
  logging, or other side effects. Reassigning the same value must be a no-op.
- Don't use a bare `default:` in a `switch` over an enum. Enumerate every case
  so adding one is a compile error, not a silent fall-through. For non-frozen
  enums from other modules (e.g. `UNAuthorizationStatus`), handle known cases
  explicitly plus `@unknown default:`, which still flags newly added cases.
- **Non-obvious types get a brief doc comment** on the type. Detectors,
  geometry/algorithm helpers, and the like state what they do and their key
  invariants. Name heuristic thresholds and document their units and decision
  meaning beside the owning policy. Explain non-obvious evidence decisions
  beside the algorithm.

### Errors and failure

- **Preserve errors until the reporting boundary.** Carry the original `Error`
  through services and observable failure state. Derive display text at the
  UI boundary and attach the error through the logging API.
- **Never silently swallow errors.** Core APIs surface failure by `throw`ing
  (or returning a `Result`/typed error). Never absorb it into a benign-looking
  default like `[]`, `nil`, or `false`. Don't discard errors with `try?` or an
  empty `catch {}` that hides the failure. At minimum a `catch` must log
  (a `warning`/`error` on the relevant `WhereLog` scope, ideally a typed
  `LogEvent` carrying a `LogAttachment.error`) *and* leave observable state honest (preserve the
  last good value or move to a `failed` state — not a default that reads as
  success, e.g. an empty list rendering as "all clear"). Callers decide *how* to
  react (rethrow, log + keep state, set a `failed` case). The failure must
  always be observable — in logs, in state, or both.
- **Distinguish user failures from programmer errors.** User/recoverable failures
  must throw (or surface honest UI state) and log. Impossible/misconfigured
  states — corrupt bundled resources, duplicate step IDs, invalid invariants —
  use `precondition` / `assertionFailure` in debug with a minimal safe fallback
  in release. Do not paper over them with silent `??` defaults that read as
  success. "Degraded but handled" recovery belongs at `warning`, not hidden.

### Persistence and wire formats

- **Prefer compiler-synthesized `Codable`.** A hand-written conformance needs a
  load-bearing reason, documented on the conformance itself (see
  `LogJournalEntry`). A simple struct of primitives just uses the synthesized
  one (see `CalendarDay`). Two reasons qualify: **(a) a single-value wire
  shape** — a bare id string or UUID rather than a wrapped object (`Region`
  encodes as `"us-CA"`, not `{"rawValue":…}`). And **(b) a composite identity
  key**, which must be a `store://` URL via Where's `WhereStoreURLCodable`
  (parsed/built with `StoreURL`). Never use an ad-hoc joined `type:value` string.
- **Keep persisted formats rename-safe.** Anything persisted (journals,
  backups, stored preferences) must survive Swift-side renames. Synthesized
  coding of an enum with associated values freezes the *case names* into the
  wire format. Renaming a case silently breaks old data. Do not hand-roll
  a keyed `Codable` to paper over missing fields from an older shape. Reshape
  the data instead (see the no-in-app-migration rule in
  [`Where/WhereCore/AGENTS.md`](../../Where/WhereCore/AGENTS.md)).
- **Persist coupled preferences as one encoded value.** Use the domain's
  `Codable` struct instead of parallel keys that can disagree. Keep missing and
  invalid-value policies explicit at the owning preference.

### UI construction

Load the [`building-ui`](../skills/building-ui/SKILL.md) skill when
creating, changing, or reviewing a SwiftUI/UIKit surface. It owns the general
view/model boundary, reuse, binding, Broadway stylesheet, layout,
accessibility, localization, UIKit-bridge, preview, and image-snapshot
procedures. Module `AGENTS.md` files add only their local seams and invariants.

Resolve authored appearance from available Broadway traits during stylesheet
slicing. This includes dimensions, layout policies, colors, and motion.
Views consume component styles, not raw styling traits or trait flags copied
into a global style. Keep measured geometry and runtime-only inputs in views.
Document each direct trait-read or `@ScaledMetric` exception at its declaration:
state which required input is unavailable during slicing. A non-`Equatable`
rendering type alone is not an exception; use an `Equatable` policy or descriptor.

SF Symbols use SFSafeSymbols' `SFSymbol` and `systemSymbol` overloads. Never
spell a symbol as a raw string or construct an unchecked `SFSymbol`. Run
`./sf-symbols --lint`. `WhereShortcuts.swift` is the sole exception because the
App Shortcuts metadata macro requires compile-time string literals.

### Repo hygiene

- Generated `.xcodeproj` and `Derived/` are git-ignored. Never commit them.
- Bundle IDs follow `com.stuff.<suffix>`.

### Modeling state

**Make invalid states unrepresentable.** When a set of values is only
meaningful in certain combinations, model it as a *single* type. Usually that is an
`enum` with associated values. Do not use parallel properties that can drift
into nonsensical combinations. Separate stored properties are the exception
to justify, not the reflex.

Worked examples, smallest to largest:

- `YearReportModel.LoadState` (`idle`/`loading`/`loaded`/`failed`) instead of
  `isLoading` + `error` + `data`, and `CalendarContentView`'s single
  `Result<[CalendarMonth], Error>?` — success and failure can't both be set,
  and "not loaded yet" is the `nil`.
- **LifecycleKit's typed `LaunchPlan`** applies it to *wiring*. Steps are
  types whose `Input`/`Output` must chain through the plan's combinators. A
  mis-ordered launch or a consumer without its producer is a compile error.
  Value-producing steps cannot be skipped. A hole in the data flow
  cannot be spelled either (PR #116).
- **`WhereScope`** applies it to *ownership*. The logged-in world is one
  value. That is the open store's services, the preferences driving it, and the log
  store they record into, created whole and never reconfigured. A
  logged-in surface can't read one world's store against another world's
  preferences (PR #150).

Smells that signal a missing type:

- **Several `Bool`s/optionals encoding one state machine** (`isLoading` +
  `loadError` + `value`) — collapse into an `enum` whose cases carry exactly
  the data each state needs.
- **Parallel collections kept in lockstep by index** — use one array of a
  small named struct.
- **Sentinel values standing in for "absent"** (`-1`, `""`, `Date.distantPast`)
  — use `Optional` or a dedicated case.
- **A `kind` tag beside optionals only valid for some kinds** — use an `enum`
  with associated values.
- **Preconditions that reject cases from an accepted enum** — use a smaller
  enum and convert explicitly.
- **Stringly-typed status or flags** (`status == "active"`) — use a typed enum,
  per the identifier/keys convention above.

### Composition: create once, inject down

**A shared resource is created exactly once, at the composition root.** It
reaches every consumer by injection. Use init parameters, explicit arguments,
or a composition hook. Never re-resolve a global. Template: the Where
app's SwiftData store (the launch's `resolve-scope` step is the process's only
open. The resulting `WhereScope` carries it. The App Intents stack derives from
it via the `onServicesReady` hook). Two subsystems independently "opening the
same store" once raced a fresh install into a launch failure.

**Create it when it's needed, not before.** That step runs *behind* the
onboarding gate. An install whose user never onboards opens nothing. A
second world (demo mode) is another scope rather than a flag threaded through
the first. See [`Where/AGENTS.md`](../../Where/Guidance/launch.md#scopes-and-the-launch).

- **An alternate boot stack is a runtime implementation, not a mode switch.**
  Select one class-bound application runtime at process initialization and
  forward lifecycle/root calls through it. Never thread a launch-mode enum or
  repeated `if` checks through app code. Where's DEBUG Inspector runtime is the
  reference.
- **No singletons or static get-or-create registries** for anything that can
  be injected. A global invites the double-create race and forces tests to
  share process-wide state. Needing `@Suite(.serialized)` plus a reset hook
  is the smell. Injected dependencies get hermetic per-test instances.
- **When the platform instantiates the consumer** (App Intents, extension
  principal classes), use the platform's DI seam. Keep it a **handoff,
  not a factory**. The root installs what it created
  (`IntentServices.install(_:)`). Early callers await installation
  (`current()` parks, cancellation-aware). The seam never creates the
  resource itself. A "create it myself" fallback quietly reintroduces the
  duplicate the design exists to prevent.
- **Derive, don't re-derive.** A stack built from an existing layer reuses
  what that layer computed (the store, the live attributor, the clock).
  Derivation stays synchronous and non-throwing. It cannot drift from its
  base.
- **Re-fire composition hooks wherever the lifecycle re-creates the thing.**
  `onServicesReady` fires on every session (re)start. Consumers always
  hold the current instance, never the first one.

This is [Modeling state](#modeling-state) applied to ownership and lifetime.
One owner, created in one place, the illegal wirings unrepresentable.
