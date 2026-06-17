# Open PR comments — #25 (LifecycleKit follow-ups)

Tracking doc for the unresolved review threads on
[PR #25 "LifecycleKit: a declarative app-startup microframework"](https://github.com/kyleve/Stuff/pull/25),
captured so they can be addressed in a follow-up PR (or split across a few).

**Snapshot:** 28 unresolved review threads. There are no open issue-level
comments and no review-summary bodies — everything below is an inline thread.
All comments are from @kyleve.

**Status (follow-up branch `pr25-lifecyclekit-followups`):** all actionable
threads are addressed across the commits below. The two non-code items are a
re-review progress marker (A, no action) and a SwiftFormat limitation (H, no
0.60.1 rule exists); localization (F) landed the requested `TODO`s with full
localization tracked as a larger follow-up. See the resolution map next.

**How to read this**

- **[new]** — raised during the latest re-review and *not yet replied to*. These
  are the freshest asks.
- **[ack]** — already has an "Posted by an AI agent… leaving open" reply
  acknowledging it as a follow-up; recorded here so nothing is lost.
- A few items are **questions** I can already answer from the code — those have a
  **Findings** note so you can just confirm and act.
- Re-review **bookmark:** the last re-review stopped at
  `Where/WhereCore/Sources/BackupCoordinator.swift:9`
  ("Got to here on re-review"). Files/areas below that point in the diff have not
  been re-reviewed yet, so expect more comments on a future pass.

---

## Resolution map

Each thread below, with how it was addressed and the commit that did it
(`git log main..pr25-lifecyclekit-followups`). ✅ = done, ℹ️ = no action needed,
⚠️ = blocked by tooling.

**A. WhereCore**
- ✅ LocationIngestor data loss on restart — durable `LocationOutbox`
  (`FileLocationOutbox`) mirrors the retry queue, drains it on `start()`, and is
  cleared by `quiesce()`. *(WhereCore: persist the location retry backlog across launches)*
- ✅ `WherePreferences.Keys` → `String, CaseIterable`. *(WhereCore: make WherePreferences.Keys a CaseIterable String enum)*
- ✅ Backup autoreleasepools around the export/import asset loops. *(WhereCore: autoreleasepool around backup asset I/O loops)*
- ℹ️ `BackupCoordinator.swift:9` — re-review bookmark, not an action item.

**B. WhereUI**
- ✅ `WhereSession` retain cycle — confirmed none; added a deinit regression test. *(WhereUI: test WhereSession deinits while observing authorization)*
- ✅ AppDelegate notification wiring moved into the launcher. *(Where: move foreground-notification wiring into the launcher)*

**C. Runner & phase**
- ✅ IDs → `AnyHashable` (+ AGENTS note). *(LifecycleKit: type step IDs as AnyHashable + validate uniqueness)*
- ✅ `reason` moved onto the `State` enum. *(LifecycleKit: move reason onto the runner's State enum)*
- ✅ `reset(_:)` → `teardown(_:)`. *(LifecycleKit: rename LifecycleRunner.reset(_:) to teardown(_:))*
- ✅ Fold remaining stored props into local state — per-step presentation
  bookkeeping is now a `runStep`-local `ActivePresentation` (can't outlive the
  step); `phase`/`teardownSteps` stay as documented top-level state. *(LifecycleKit: scope per-step presentation state to the running step)*

**D. `LifecycleStep` API**
- ✅ Validate step-ID uniqueness (debug assert in the builder). *(same commit as AnyHashable IDs)*
- ✅ `modes` + `condition` ("replacing"/gating) moved into the initializer; `run` → `perform`. *(LifecycleKit: fold step modes/condition into init, rename run -> perform)*
- ✅ `minVisible` on every `presenting` overload, unified into one presentation value. *(LifecycleKit: unify presentation minVisible across all triggers)*
- ✅ `AnyView` vs `some/any View` — kept `AnyView` deliberately, documented why. *(LifecycleKit: document why presentation UI is type-erased to AnyView)*

**E. Presentation, container & transitions**
- ✅ Splash/failure surface transitions — first-class `transition`/`animation`
  on the container, keyed on `LifecyclePhase.surfaceIdentity`. *(LifecycleKit: animate container surface transitions)*
- ✅ Assert-in-debug / no-op-in-prod wrapper for the env runner — `LifecycleRunnerProxy`. *(LifecycleKit: publish runner via assert-in-debug LifecycleRunnerProxy)*

**F. Localization**
- ✅ `TODO`s left at the user-facing string sites; full localization is the larger follow-up. *(LifecycleKit: TODO to localize the failure view's strings)*

**G. Tests & docs**
- ✅ `LifecycleContainerTests` fixtures inlined per test. *(LifecycleKit: make container tests self-contained, drop RenderFlags)*
- ✅ Fuzz / adversarial step-sequence tests (`LifecycleRunnerFuzzTests`). *(LifecycleKit: add seeded fuzz tests for runner step sequences)*
- ✅ AGENTS.md + README re-reviewed against the final API. *(LifecycleKit: re-review README + AGENTS for the final API)*

**H. Tooling**
- ⚠️ Force a trailing closure's body onto its own line — no SwiftFormat 0.60.1
  rule does this; `.swiftformat` unchanged. Revisit when a newer rule lands.

---

## A. Where app — WhereCore

### `Where/WhereCore/Sources/LocationIngestor.swift:54` — confirm no data loss on app restart  [new, 2026-06-17]
> Reading this comment, can we confirm we don't lose data on app restart too, right?

**Findings:** Partial data loss is real. The retry queue is an **in-memory**
`[LocationSample]` (`retryQueue`, not persisted anywhere). Samples that have been
*committed* to the store are safe (SwiftData), but any sample sitting in the
retry queue because its persist failed (transient SwiftData/CloudKit error) is
**lost if the app is terminated/relaunched before the queue drains** — and
significant-change / Visits events generally aren't re-delivered by iOS after the
fact, so they don't come back on their own.

**Suggested:** if we want at-least-once durability across launches, persist the
retry backlog (a small durable "outbox" — e.g. a file or a dedicated store
table) and drain it on `start()`. Worth weighing against complexity, since the
window is "persist failed AND app died before the next successful save."
Note: `quiesce()` intentionally *drops* this queue on reset/erase (commit
`edc5e87`) — a durable outbox would need clearing there too.
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3424780689)

### `Where/WhereCore/Sources/WherePreferences.swift:89` — make `Keys` a `String` `CaseIterable` enum  [new, 2026-06-17]
> Let's make this a real `enum` backed by `String` so we can instead of enumerating `all`, we can just conform it to `CaseIterable`.

**Context:** `Keys` is currently a caseless `enum` of `static let` strings plus a
hand-maintained `static let all = [...]` used by `reset()`. Converting to
`enum Keys: String, CaseIterable { case hasOnboarded = "where.hasOnboarded" … }`
drops the manual `all` array (use `Keys.allCases`) and makes "did you add the new
key to reset()?" a non-issue. Call sites move from `Keys.hasOnboarded` to
`Keys.hasOnboarded.rawValue` (getters/setters + `reset()`).
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3424822781)

### `Where/WhereCore/Sources/BackupCoordinator.swift:94` — autoreleasepools to reduce memory pressure  [new, 2026-06-17]
> Consider: Autoreleasepools around these areas to reduce memory pressure

**Context:** backup export/import walks potentially large sample/evidence sets.
Wrapping the per-batch/per-iteration body in `autoreleasepool { … }` keeps
transient autoreleased objects (Data blobs, encoder scratch) from piling up until
the enclosing scope exits. Profile first to confirm it's worth it.
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3424761113)

### `Where/WhereCore/Sources/BackupCoordinator.swift:9` — re-review bookmark (not an action item)  [new, 2026-06-15]
> Got to here on re-review

**Context:** progress marker, not a request. Signals the re-review pass stopped
here; code after this point in the diff hasn't had a second look.
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3410809296)

---

## B. Where app — WhereUI

### `Where/WhereUI/Sources/Model/WhereSession.swift:168` — confirm no leak / retain cycle  [new, 2026-06-17]
> Confirming there's no leak / retain cycle here right?

**Findings:** No retain cycle.
- `authorizationTask` captures `[weak self]` and binds `services` (a `Sendable`
  value type) locally so the long-lived stream loop doesn't pin the session; the
  task is cancelled in `deinit`.
- The backup-progress observer task also captures `[weak self]`.
- `preferences` and `services` are held by reference but neither holds a
  back-reference to the session/model, so there's no cycle through them.

Worth a quick sanity re-check that every long-lived `Task` on the session uses
`[weak self]` and that their `AsyncStream` continuations finish (so the loops
actually exit), but I don't see a leak.
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3424905605)

### `Where/Where/Sources/AppDelegate.swift:44` — move into launcher setup?  [ack, 2026-06-13]
> can/should we move this into the launcher setup?

**Context:** this is the foreground-notification-presentation delegate wiring.
Folding it into the launcher's `initializePrerequisites` (or a dedicated step)
would keep app-lifecycle wiring in one place. Left as a follow-up.
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3407428418)

---

## C. LifecycleKit — runner & phase (state modeling)

### `Shared/LifecycleKit/Sources/LifecyclePhase.swift:18` — IDs should be `AnyHashable`/`Hashable`, not `String` (+ AGENTS.md)  [new, 2026-06-16]
> Let's change this to AnyHashable instead. In general, IDs should be AnyHashable or Hashable vs. a string. Let's update AGENTS.md to reflect that.

**Context:** cross-cutting type change. Touches `LifecycleFailure.stepID: String`,
`LifecycleStep.id: String`, and `LifecyclePhase.runningStepID: String?`, plus the
Where app's `LaunchStepID` enum (which is already a typed enum — it'd just need a
`Hashable` raw representation). Retry/teardown matching compares
`step.id == failure.stepID`, which stays correct under `AnyHashable`/`Hashable`
(both `Equatable`). Also add a note to `AGENTS.md` codifying "IDs are
`Hashable`/`AnyHashable`, not raw strings."
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3424609515)

### `Shared/LifecycleKit/Sources/LifecycleRunner.swift:51` — move `reason` onto the state type  [new, 2026-06-16]
> Instead of switching here, let's move this into a `reason` property on the state type itself.

**Context:** `LifecycleRunner.reason` currently `switch`es over the private
`State` enum. Add a `var reason: LifecycleReason` to `State` (each case already
carries it) and reduce the runner's accessor to `state.reason`. Small, contained.
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3424629589)

### `Shared/LifecycleKit/Sources/LifecycleRunner.swift:136` — rename `reset(_:)` to `teardown`?  [new, 2026-06-15]
> Maybe lets just rename this `teardown`?

**Context:** points at the public `reset(_:)` method. Note commit `64ddaf9`
already adopted "teardown" for the *concept* (the retained `teardown` steps + the
`driveReset` helper). Renaming the public method `reset(_:)` → `teardown(_:)`
(and `driveReset` → `driveTeardown`) would make naming consistent. Confirm intended
spelling before renaming the public API; the app calls this from `WhereLaunch`.
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3410782319)

### `Shared/LifecycleKit/Sources/LifecycleRunner.swift:37` — fold remaining stored props into the state enum  [ack, 2026-06-13]
> Great to see this! However when I earlier said that all state should be stored in the enum with associated values, I meant it. This is a half try; there's still a lot of stored properties that seem like they could be invariants with the local state. Any way to fix?

**Context:** the bigger architectural ask. Stored props that could become
associated values / be unrepresentable-when-invalid: `phase`, `teardown`,
`presentationTask`, `deferredShownAt`, `deferredMinVisible`. e.g. the deferred
presentation bookkeeping only makes sense while a step is `running`. This is the
most involved item here — likely its own PR.
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3407405242)

---

## D. LifecycleKit — `LifecycleStep` API

### `Shared/LifecycleKit/Sources/LifecycleStep.swift:15` — validate step-ID uniqueness  [ack, 2026-06-13]
> Do we validate the uniqueness of these?

**Context:** no uniqueness validation in LifecycleKit today. Options: assert in
`LifecycleSteps` builder (debug), or dedupe. The Where app side already removed
the duplicate-raw-string risk via the `LaunchStepID` enum (`ec3a9f8`). Ties into
the `AnyHashable` ID change above.
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3407412443)

### `Shared/LifecycleKit/Sources/LifecycleStep.swift:44` — move `modes` into the initializer  [ack, 2026-06-13]
> I still want to see this in the init instead of as a "modifier".

**Context:** `allowedModes` is currently set via a `.modes(_:)` modifier; reviewer
wants it as an init parameter (compile-time required/visible rather than an
easy-to-forget chained call).
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3407414169)

### `Shared/LifecycleKit/Sources/LifecycleStep.swift:36` — "replacing" semantics → init parameter  [ack, 2026-06-13]
> Replacing to me indicates this should also be an init parameter!

**Context:** same theme as :44 — a modifier whose "replace" semantics suggest it
belongs in the initializer.
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3407416329)

### `Shared/LifecycleKit/Sources/LifecycleStep.swift:112` — rename to `perform`?  [ack, 2026-06-13]
> Hmm maybe `perform`?

**Context:** naming nit on the step's run/body member; reviewer floats `perform`.
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3407418478)

### `Shared/LifecycleKit/Sources/LifecycleStep.swift:147 & :145` — add `minVisible` here too (+ unify presentation prefs)  [ack, 2026-06-13]
> Let's add min visible here too
>
> (Maybe we should have prefs for presentation to unify this across triggers?)

**Context:** two adjacent presentation factory/overloads lack the `minVisible`
knob the deferred path has. Reviewer also floats unifying presentation options
(`after` / `minVisible` / etc.) into one "presentation prefs" value shared across
triggers instead of per-overload parameters.
[links: [:147](https://github.com/kyleve/Stuff/pull/25#discussion_r3407420057) ·
[unify](https://github.com/kyleve/Stuff/pull/25#discussion_r3407420734) ·
[:145](https://github.com/kyleve/Stuff/pull/25#discussion_r3407420206)]

### `Shared/LifecycleKit/Sources/LifecycleStep.swift:106` & `Shared/LifecycleKit/Sources/StepHandle.swift:29` — `some View`/`any View` instead of `AnyView`?  [ack, 2026-06-13]
> Can this not return some View or any View?
>
> Same as above can we make this a some View or any View?

**Context (my reply on the thread):** kept as `AnyView` deliberately — the UI
builder is stored type-erased so heterogeneous steps share one `[LifecycleStep]`
array; `some View` can't be stored without leaking the concrete view type into
`LifecycleStep`/`LifecycleSteps`/the builder. Erasure is confined to one stored
closure. Left open in case you'd prefer a fully generic step design despite that
trade-off — decide both threads together.
[links: [LifecycleStep](https://github.com/kyleve/Stuff/pull/25#discussion_r3406917275) ·
[StepHandle](https://github.com/kyleve/Stuff/pull/25#discussion_r3406936302)]

---

## E. LifecycleKit — presentation, container & transitions

### `Shared/LifecycleKit/Sources/LaunchContainer.swift:33 & :37` — transitions for splash/failure surfaces  [ack, 2026-06-12]
> Should this have a transition of some sort? Maybe if the scene phase is visible?
>
> These should definitely have some sort of transition; though perhaps the provider can just provide those all?

**Context (my reply):** splash/failure surfaces are now caller-injected
(`90ae902`), so a caller can attach its own transition; no built-in,
scene-phase-aware transition was added. Left open to decide whether the container
should offer first-class transition support.
[links: [:33](https://github.com/kyleve/Stuff/pull/25#discussion_r3406715677) ·
[:37](https://github.com/kyleve/Stuff/pull/25#discussion_r3406718800)]

### `Shared/LifecycleKit/Sources/LifecycleContainer.swift:8` — assert-in-debug / no-op-in-prod wrapper for the optional  [ack, 2026-06-13]
> Could we write an intermediate type for this, so if the actual value is nil, we can assert in debug and no-op in prod?

**Context:** wrap the optional in a small helper that traps/asserts in debug but
no-ops in release when `nil`, instead of silently doing nothing. A dedicated
LifecycleKit follow-up.
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3407351572)

---

## F. LifecycleKit — strings / localization

### `Shared/LifecycleKit/Sources/LifecycleFailureView.swift:16 & :20` — localize strings (+ leave a TODO)  [new + ack]
> We need to localize this (and any other strings in LifecycleKit)
>
> Also needs to be localized!
>
> **[new, 2026-06-15]** Can we leave a TODO for these type of strings please?

**Context:** LifecycleKit's user-facing strings (failure view, etc.) are hardcoded
and need localization. The concrete near-term ask (`[new]`) is to drop a `TODO`
at these string sites now, with full localization as the larger follow-up.
[links: [:16](https://github.com/kyleve/Stuff/pull/25#discussion_r3407390818) ·
[:20](https://github.com/kyleve/Stuff/pull/25#discussion_r3407392996) ·
[TODO ask](https://github.com/kyleve/Stuff/pull/25#discussion_r3410765910)]

---

## G. LifecycleKit — tests & docs

### `Shared/LifecycleKit/Tests/LifecycleContainerTests.swift:16` — inline the default values per test  [new, 2026-06-15]
> Instead of defining default values on the type, let's move them to each test. de-dupe as needed,

**Context:** shared default fixtures on the test type should move into each test
(de-duping where it makes sense) so each test reads self-contained.
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3410793392)

### `Shared/LifecycleKit/Tests/LauncherTests.swift:25` — fuzz / adversarial tests  [ack, 2026-06-13]
> Do we have any fuzz tests or adversarial tests that ensure behavior is consistent and weird branches work as expected?

**Context (my reply):** targeted adversarial coverage was added (`c557888`/
`fe17a70`: cancel-while-parked, init-condition gating, min-visible hold,
cancellation throwing). No property-based/fuzz harness that randomizes step
sequences yet — left open to track a real fuzz suite.
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3406988509)

### `Shared/LifecycleKit/AGENTS.md:1` & `Shared/LifecycleKit/README.md:1` — please re-review  [new, 2026-06-15]
> Please re-review this file

**Context:** reviewer wants both docs re-read/refreshed (likely to reflect the
final API after the round-2 refactor: caller-injected splash/failure, `LaunchStepID`,
etc.). Pair with whatever API renames land (e.g. `teardown`, `perform`, init
params, `AnyHashable` IDs) so docs match.
[links: [AGENTS.md](https://github.com/kyleve/Stuff/pull/25#discussion_r3410803609) ·
[README.md](https://github.com/kyleve/Stuff/pull/25#discussion_r3410805010)]

---

## H. Tooling / SwiftFormat

### `Where/WhereUI/Sources/Launch/WhereLaunch.swift:50` — force trailing-closure body onto its own line  [ack, 2026-06-12]
> I don't like that this is ending up on the same line; can we update swiftformat rules so these closures always go on new lines somehow?

**Context (my reply):** SwiftFormat 0.60.1 has no rule that forces a trailing
closure's body onto its own line (`wrapArguments`/`braces` don't do this), so
`.swiftformat` was left unchanged. Revisit if a newer SwiftFormat adds the rule,
or add a custom lint.
[link](https://github.com/kyleve/Stuff/pull/25#discussion_r3406517923)

---

## Suggested grouping for follow-up PR(s)

1. **Quick wins / contained** — `WherePreferences` `CaseIterable` enum (A),
   `reason` onto `State` (C), `reset(_:)`→`teardown(_:)` rename (C), localization
   `TODO`s (F), `LifecycleContainerTests` fixtures (G).
2. **Answer & close** — data-loss-on-restart (A) and retain-cycle (B) are
   questions; confirm the findings above, decide if the durable-outbox work is in
   scope, then resolve.
3. **`AnyHashable` IDs + AGENTS.md** (C/D) — one typed-ID PR that also covers
   step-ID uniqueness validation.
4. **`LifecycleStep` API shape** (D) — `modes`/"replacing" into init, `perform`
   rename, `minVisible` + unified presentation prefs; update README/AGENTS after.
5. **State-in-enum deepening** (C) — the larger "fold stored props into the phase
   enum" refactor.
6. **Presentation transitions** (E) and **fuzz suite** (G) — larger, optional.
