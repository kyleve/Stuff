# UI guidance: previews

## Author previews and image coverage with the view

- Put at least one `#Preview` in the represented view's source file under
  `#if DEBUG`. Use synchronous, in-memory, production-shaped fixtures. Cover
  empty, loaded, failure, and distinct edge states that matter.
- When a module uses SnapshotKit, put its `SnapshotProviding` conformance in the
  same source file and render `Self.snapshotPreviews` from the preview. Declare
  the matrix once and use one `FooSnapshotTests` suite/file per represented
  view.
- Apply [SnapshotKit's coverage policy](../../../../Shared/SnapshotKit/AGENTS.md#invariants-an-agent-cant-re-derive)
  before expanding a matrix. List distinct layouts and choose representative states;
  use compact presets for additional states instead of a representative preset in
  every `allCases` iteration. Explain any exception beside its declaration.
- When reducing coverage, enumerate the retained case/configuration identities,
  remove only references no longer selected, and preserve case names used by
  previews or Flyover. Validate retained captures with `--record never`; record
  only new or intentionally reframed subjects separately and inspect their images.
- Choose theme coverage from the module's `AGENTS.md`. Prefer one component
  comparison sheet containing all supported themes for each representative state
  and trait configuration. Build fresh fixture state per panel and preserve normal
  component width, production behavior, and artwork readiness.
- For generic comparison sheets, use `SnapshotCase.cutsheet { SnapshotPanel(...) { ... } }`.
  Keep panel identities stable and choose the reference group explicitly when grouping related sheets.
  Use a module's theme helper when it supplies that module's root and theme ordering.
- Keep full-screen theme variants for critical integration or materially different
  screen composition. Do not multiply screen matrices for child-surface changes.
- Use explicit reference groups: mixed-theme sheets have a neutral group; single-theme
  screen references use a stable consumer-owned theme group. Keep existing default
  theme paths. Never encode a directory in a case name or localized theme label.
- Snapshot the production branch. Use a stand-in only for externally loaded or
  wall-clock-dependent content that no settle window can stabilize, keep its
  layout identical, and encapsulate the substitution inside the shared
  component rather than branching at every call site.
- Centralize never-settling motion behind the module's static-motion helper.
  Do not scatter `isCapturingSnapshot` checks through product views.
- Keep generic capture mechanics in SnapshotKit/SnapshotKitTesting and
  consumer-specific root wrapping in the UI module.
- For intrinsic/full-content cases whose fixture has a synchronous final
  height, set `measurementReadiness: .immediate` to avoid paying a redundant
  sizing settle. Keep `.sameAsCapture` when async work can change height, and
  never weaken the case's final `settle` to optimize measurement.
- If async content changes measured size, await its completion through `onReadyToMeasure`.
  Use `onReadyToSnapshot` for readiness that affects only final capture.
  Base both hooks on production completion signals.
  Stable pixels can still show a loading placeholder. Do not use a longer
  sleep as evidence that content loaded.
- Review every changed reference for content, navigation/tool/search chrome,
  background, safe areas, Dynamic Type, and accessibility annotations. Give a
  chrome-free capture an explicit production background instead
  of inheriting a transparent test host. A blank, clipped, incomplete, or
  visibly broken image is a product or capture defect. Fix it before recording
  a reference.
- When navigation, presentation, or lifecycle behavior changes, exercise the
  production entry point and return path on a supported runtime.
  Include re-entry or foreground activation when relevant. A static fixture
  does not exercise those paths. For device-only failures, retain a physical-device
  verification requirement and report it as unverified until exercised.

Use the [`running-tests`](../../running-tests/SKILL.md) skill to select and run the
affected unit and image suites. A view or appearance change normally requires
snapshot validation even when its unit tests pass.
