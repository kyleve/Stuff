---
name: tla-verify-protocol
description: Model-check coordination protocols with TLA+/TLC and map the result back to source behavior and deterministic tests. Use only when the user explicitly invokes this skill or asks for TLA+, TLC, or PlusCal verification of a concurrent state machine, lifecycle, queue, retry, cancellation, teardown, resource handoff, or dependency protocol. Do not trigger for ordinary Swift protocol work, general concurrency review, unit testing, or race diagnosis without an explicit formal-model request.
---

# Verify a protocol with TLA+

Verify one narrow temporal claim, not an application. Treat TLC output as
evidence about the stated model, bounds, and assumptions; never present it as
proof that the implementation is correct.

Read the repository and affected module instructions before modeling. In this
repository, use
[`Where/Specifications/TrackingReconciliation`](../../../Where/Specifications/TrackingReconciliation/README.md)
as the worked tooling and documentation reference, without copying its state
mapping into unrelated protocols.

## Establish the verification boundary

1. Read the production implementation, tests, and callers. Identify every
   entry point that can participate in the protocol, not only the method named
   in the request.
2. State one correctness question in plain language. Define its admission or
   linearization points, success and failure outcomes, repeated-call behavior,
   and treatment of work racing with shutdown or cancellation.
3. Record the source revision and files the model represents. List suspension
   points, locks, actor reentrancy, tasks, callbacks, persistence boundaries,
   and environment actions that can change ordering.
4. Stop and request direction if a missing product decision changes the
   contract materially. If the logic has no meaningful temporal behavior,
   explain why TLA+ is the wrong verification tool.

Read [`references/modeling-checklist.md`](references/modeling-checklist.md)
before authoring any model. Read only the relevant sections of
[`references/protocol-patterns.md`](references/protocol-patterns.md) for the
protocol family being checked.

## Build a traceable model

1. Create a source-correspondence table mapping each model variable and action
   to production state and code boundaries.
2. Preserve independently authoritative facts as separate variables. Do not
   collapse desired, persisted, in-flight, effective, and published state merely
   because the implementation calls all of them "state."
3. Make each action genuinely atomic. Split an async function at every await or
   callback boundary where another action can interleave.
4. Abstract data values into a small finite set while preserving identity,
   ordering, duplication, loss, and lifecycle facts relevant to the claim.
5. Model environment failures and late completions nondeterministically unless
   the production contract forbids them.

## Define properties before judging the design

Define and check:

- `TypeOK` for every variable;
- safety invariants that express the requested correctness claim;
- deadlock freedom when a terminal deadlock is not the intended model shape;
- liveness only when progress matters, with every weak or strong fairness
  assumption tied to a real runtime guarantee;
- reachability for the non-empty, in-flight, closing, failure, and terminal
  states needed to make the properties non-vacuous.

Give important properties stable names that the model README, TLC output, and
code tests can cite.

## Challenge the model

1. Check a negative control or known-broken design against the same variables,
   bounds, and properties. Require it to fail for the expected reason.
2. Inspect the counterexample rather than accepting a nonzero TLC exit status.
   Fix the model only when the trace demonstrates a mapping error; do not erase
   a production-faithful counterexample.
3. Check the current or candidate design with the same property definitions.
4. Exercise more than one small finite bound when the state space permits. If a
   claimed input dimension is fixed to one value, do not claim the model checked
   behavior in the other values.
5. Treat state explosion, timeout, uncovered actions, unexplained deadlocks, or
   fairness invented to make liveness pass as inconclusive.

## Make the check reproducible

Pin the TLC and Java versions and verify downloaded artifacts by checksum. Keep
tool caches and per-run state in ignored local build storage; isolate concurrent
runs. Do not add TLA+ to root tool configuration, repository-wide policy, or CI
unless the user explicitly requests that adoption.

When repository mutation is authorized, follow the nearest existing placement
convention. In this repository, prefer a feature-level
`Specifications/<Concern>/` folder containing:

- the `.tla` module;
- configurations for the relevant current, negative-control, and candidate
  designs;
- a `manifest.json` declaring each TLC case and its pass/fail expectation;
- a short README with the question, correspondence table, bounds, assumptions,
  exclusions, properties, results, and run command.

Run checks from the repository root with `./tla-check [<Concern> ...]` (see
[`Where/Specifications/TrackingReconciliation`](../../../Where/Specifications/TrackingReconciliation/README.md)).
The root script owns TLC/JDK download and pinning; do not add per-spec `check`
scripts or wire TLA+ into CI unless explicitly requested.

Do not force these exact filenames when the protocol needs a different model
shape.

## Translate evidence back to software

Turn each real counterexample into a source-level event timeline with file and
line references. When edits are authorized, add a deterministic regression test
that holds the implementation at the modeled interleaving; use synchronization,
not sleeps. Keep a known-broken assertion explicit until the product fix lands.

A clean candidate model must identify the implementation obligations needed to
match it: all participating entry points, atomic regions, retry paths, and
completion callbacks. Do not implement the production fix unless the user asks
for it.

Report exactly one verdict:

- **Falsified** — TLC found a source-faithful counterexample.
- **Verified for these model bounds and assumptions** — TLC exhausted the stated
  model with no error.
- **Inconclusive** — the mapping, contract, coverage, fairness, or state space
  was insufficient.

Include the exact configs and bounds, tool versions, generated/distinct-state
counts, assumptions and exclusions, counterexample or clean-run summary, and
links to the model and deterministic guard. Relevant implementation changes
invalidate the result until the mapping and model are checked again.
