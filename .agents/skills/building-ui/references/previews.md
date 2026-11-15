# UI guidance: previews

## Author previews and image coverage with the view

- Put at least one `#Preview` in the represented view's source file under `#if DEBUG`.
  Use synchronous, in-memory, production-shaped fixtures for meaningful empty, loaded, failure, and edge states.
- Add image references where a view owns distinct visual risk. Preview and Flyover states do not each require recorded references.
- For views with SnapshotKit coverage, colocate `SnapshotProviding` and render `Self.snapshotPreviews`. Declare the matrix once and use a matching snapshot suite/file.
- Read [SnapshotKit's contract](../../../../Shared/SnapshotKit/AGENTS.md) before authoring cases: it owns matrix selection, frames, motion substitutions, fixture isolation, and measurement/capture readiness.
  Explain coverage exceptions beside their declarations. Encapsulate permitted substitutions and static-motion helpers in shared components instead of scattering capture checks through callers.
- Read the module's theme-coverage rules. Prefer comparison sheets for component appearance and full-screen variants for critical integration or materially different composition.
  Do not multiply screen matrices for child-surface changes. Use the module's theme helper when available.
- Keep reference groups explicit and consumer-owned: neutral for mixed themes, stable theme groups for full screens, preserving default paths.
  Never encode directories in case names or derive them from localized labels.
- On matrix reduction, enumerate retained case/configuration identities, remove only unselected references, and preserve names used by previews or Flyover.
  Follow [running-tests](../../running-tests/SKILL.md#snapshots) for separate recording and assertion runs.
- Review changed references for content, chrome, background, safe areas, Dynamic Type, and annotations.
  Chrome-free captures need an explicit production background. Fix blank, clipped, incomplete, or broken images before recording.
- For navigation, presentation, or lifecycle changes, exercise the production entry point and return path, including relevant re-entry/foreground behavior.
  Static fixtures do not exercise those paths. Retain physical-device verification for device-only failures and report it unverified until exercised.

Use [running-tests](../../running-tests/SKILL.md) to select and run affected suites. Appearance changes normally require snapshots even when unit tests pass.
