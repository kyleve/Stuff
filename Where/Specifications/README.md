# Formal protocol specifications

This directory contains an opt-in Lean 4 verification prototype beside the
existing TLA+/TLC models. Lean is pinned by `lean-toolchain`; Lake builds the
repo-owned protocol library and the nine `Model.lean` modules beside their
TLA+ models, with only Lean's `Std` library.

Run all proof modules and all 25 diagnostic cases from the repository root:

```sh
./lean-check
```

Use `./lean-check --list` to list model names or pass one or more names to run a
subset. The script installs checksum-pinned Elan in ignored `.build/lean/`
storage, and Elan installs the checked-in Lean toolchain in that isolated home.
The command is not part of CI or `./test`.

## Guarantees and evidence

Each model defines typed state, typed actions, a partial transition function,
and stable property names matching its TLA+ predecessor. Current-design safety
claims are kernel-checked theorems proved by induction over `Reachable`.
Negative controls and reachability controls are kernel-checked witness traces.
The exact breadth-first search is diagnostic: it reports state counts and
shortest counterexample action sequences, but its result is never used as proof
evidence. No proof may use `sorry`, `admit`, new axioms, or `native_decide`.

`Protocol.lean` owns labelled traces, infinite behaviors,
stuttering, `Eventually`, `LeadsTo`, TLA-compatible weak fairness, and exact
search whose hash table resolves collisions with state equality.

## Prototype limitation

The Lean package currently proves safety and checks all former finite cases,
but it does not yet prove `EventuallySettled`,
`DeliveredRemovalEventuallyStops`, or
`DeliveredRemovalEventuallyRetires` from the TLA models' weak-fairness
assumptions. It also lacks kernel theorems for the two models whose TLC configs
check deadlock freedom. TLA+/TLC therefore remains authoritative for those
obligations and must not be removed until the unbounded Lean theorems exist.

The models remain abstractions of Swift. Their READMEs and deterministic Swift
guards are the source-correspondence contract; a proof of an outdated or
inaccurate transition system says nothing about production behavior.
