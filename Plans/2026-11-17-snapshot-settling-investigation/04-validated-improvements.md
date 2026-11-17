# 04 — Deliver validated improvements

- Status: outline
- Depends on: [03](03-controlled-experiments.md).
- Shared context: [Overview](README.md).

## Intended outcome

Implement R-04: retain improvements supported by the experiments and report matched before/after savings with unchanged content, geometry, references, and tolerances.
Preserve X-02–X-04. Prefer one independently verified change per commit and PR slice.

## Known boundaries and learning needed

A readiness signal belongs to the operation and mount that completed it. Rehosting, retries, cancellation, resize, native chrome, scrolling, and accessibility may invalidate earlier evidence.
A passing reference assertion alone does not prove that earlier capture is complete or pixel-identical.
No architecture is selected yet; diagrams and Swift sketches depend on the experiments rather than a speculative global coordinator.

## Refinement trigger

When plan 03 supports a candidate, detail its affected consumers, lifecycle/error contracts, focused guards, integration coverage, and before/after protocol.
If no candidate qualifies, record the supported negative results and reconcile remaining work with STU-121.

## Resume point

Await plan 03. No optimization implementation is started or promised by the instrumentation PR.
