# Modeling checklist

## Source correspondence

- Record the represented commit and source files.
- Map each variable to one authoritative production fact.
- Map each action to an atomic source region.
- Split actions at awaits, callbacks, lock release, task creation, actor hops,
  persistence completion, and cancellation observation.
- Put an explicit PlusCal label at every modeled atomicity boundary.
- Use parallel assignment when updated values must all read the same pre-state.
- List callers and environment events that can enter the protocol concurrently.
- Document every abstraction and atomicity assumption.

## State and actions

- Keep desired, persisted, queued, in-flight, effective, and published state
  separate when they can disagree.
- Use small identity-bearing tokens when loss, duplication, or ordering matters.
- Represent lifecycle as a typed state rather than several unrelated flags.
- Include failure, retry, cancellation, repeated calls, and late completion when
  the implementation permits them.
- Keep bounds small enough to explore but large enough to exercise the claim.

## Properties

- Check types for every variable.
- Express safety in domain language: no loss, no duplicate completion, no write
  after teardown, ownership is unique, or output matches the latest intent.
- Check deadlocks unless a terminal deadlock intentionally represents completion.
- Add liveness only with runtime-backed fairness assumptions.
- Name properties so counterexamples, docs, and code tests can cross-reference
  them.

## Anti-vacuity

- Require reachability of every premise used by an important invariant.
- Require traces through non-empty, in-flight, failure, closing, and terminal
  states as applicable.
- Run a negative control that violates the exact property being claimed.
- Vary constants for every input dimension named in the result.
- Reuse identical property definitions for broken/current/candidate designs.
- Inspect the trace and final values; do not accept only TLC's exit code.

## Evidence to retain

- TLC and Java versions plus downloaded-artifact checksums.
- PlusCal translation status and the retained generated-module path.
- Configurations, constant values, bounds, fairness, and state constraints.
- Generated and distinct states, graph depth, deadlock result, and property
  results.
- A source-level rendering of each counterexample.
- A deterministic regression test for any implementation-faithful trace.

Use only **falsified**, **verified for these model bounds and assumptions**, or
**inconclusive** as the final verdict.
