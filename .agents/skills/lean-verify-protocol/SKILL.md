---
name: lean-verify-protocol
description: Prove coordination-protocol safety and liveness with the repository's Lean 4 transition-system library, add checked witness traces and diagnostic search, and map the result back to source and deterministic tests. Use when the user explicitly requests Lean formal verification or asks to create, change, or review a Lean protocol specification. Do not trigger for ordinary Swift protocol work, unit testing, or a general concurrency review without a formal-verification request.
---

# Verify a protocol with Lean

Verify one narrow temporal claim, not an application. A kernel-checked theorem
proves the stated transition system; it does not prove that the model matches
the implementation.

Read the root and affected module instructions, production implementation,
callers, tests, and the nearest specification README before editing a model.
Use `Where/Specifications/Protocol.lean` rather than
introducing another transition-system dependency.

## Establish source correspondence

1. State the correctness question, admission or linearization points, terminal
   states, repeated-call behavior, and racing shutdown or cancellation.
2. Map every state field and action to production state and a source boundary.
   Split async work at each suspension or callback where another action can
   interleave.
3. Keep independently authoritative desired, persisted, in-flight, effective,
   and published facts separate.
4. Record assumptions and exclusions. Stop if a missing product decision
   materially changes the contract.

## Build the typed model

Define an algebraic `State`, `Action`, configuration values, finite initial
states, and an executable partial `step`. Construction-time types replace TLA+
`TypeOK`; retain a named semantic-validity predicate only for relationships the
types cannot express. Preserve established property names so READMEs, old TLC
results, and Swift test comments stay traceable.

Model stuttering explicitly in infinite behaviors. Tie each weak-fairness
assumption to a real runtime progress guarantee. Never add fairness merely to
make a liveness theorem provable.

## Prove and challenge

1. Prove each current safety invariant by induction over `Reachable`. Add a
   private inductive strengthening when the public property alone is not
   inductive.
2. Prove liveness for every infinite `Behavior` satisfying the stated weak
   fairness. Bounded search is not a substitute.
3. Prove deadlock freedom when the corresponding protocol treats deadlock as
   an error.
4. Express each known-broken design as a checked finite `Trace` ending in the
   expected named violation. Express reachability controls as checked witness
   traces.
5. Run exact diagnostic breadth-first search with the same properties. Inspect
   the source-level event sequence of every counterexample; state counts and
   depths need not match TLC when typed state changes the graph.

Proof evidence may use kernel-checked tactics such as `decide`, `simp`, `omega`,
and `grind`. It may not contain `sorry`, `admit`, a new axiom, or
`native_decide`.

## Validate and report

Run `./lean-check [<Concern> ...]`, selected-spec execution, and any applicable
deterministic Swift guard. Keep the tool opt-in unless the user explicitly asks
to change CI. Relevant source changes invalidate the result until model
correspondence is reviewed again.

Report exactly one qualified verdict:

- **Proved for this model and assumptions** — every required kernel theorem is
  present and diagnostic controls behave as expected.
- **Falsified** — a checked witness or diagnostic trace exposes a
  source-faithful counterexample.
- **Inconclusive** — source correspondence, fairness, proof coverage, or the
  state space is insufficient.

List theorem names, configurations, assumptions, exclusions, diagnostic state
counts, counterexample or witness sequences, and deterministic implementation
guards. If a required liveness or fairness theorem is missing, retain the TLA+
model and say so explicitly.
