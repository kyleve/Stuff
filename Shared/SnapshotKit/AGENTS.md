# SnapshotKit – Module Shape

SnapshotKit supplies shared preview and image-test cases and appearance matrices. See [README.md](README.md) for its API.
Read the root [AGENTS.md](../../AGENTS.md) first.

## Scope & dependencies

Use SwiftUI, Foundation, and UIKit only. Shipping UI modules link SnapshotKit for previews; never pull in SnapshotTesting, XCTest, Broadway, or WhereUI.
Capture, comparison, and accessibility annotation rendering belong to test-only [SnapshotKitTesting](../SnapshotKitTesting/AGENTS.md).
Consumer modules own design-system root wrapping.

## Invariants an agent can't re-derive

- Choose the smallest explicit matrix that covers distinct layout and appearance risks. Use a preset only when its axes add useful coverage.
  Cover shared rendering at its owning component; keep focused integration captures in wrappers.
  Additional states can use one baseline. Repeat dark, AX5, contrast, tablet, or annotations for a specific state-dependent risk.
  Use focused configurations without a Cartesian product. Document repeated representative matrices at their declarations.
- Keep configuration selection explicit; case/assertion APIs must not supply a broad default matrix.
  Treat identifiers as a reference-file wire format: omit default axes, preserve existing tokens and frame semantics, and omit a new axis's default. Guard: `SnapshotConfigurationTests`.
- Filter `.accessibility` configurations out of previews. Including them requires a preview-only dependency boundary for the test-only renderer.
- Preview cutsheets require one case per `(referenceGroup, name)` identity. Distinct configurations do not distinguish repeated case identities.
  Preview fixtures must load from their mounted view or start ready; previews do not invoke capture readiness hooks.
- Keep content and panel builders lazy. Descriptor construction must not instantiate views/models.
  Models captured outside a builder and shared hooks still require independent cases; per-configuration builder invocation does not isolate them. See [STU-114](https://linear.app/kve/issue/STU-114).
  The scoped demo-world reuse exception for two noninteractive WhereUI image matrices is owned by [WhereUI test contracts](../../Where/WhereUI/Tests/AGENTS.md); their case/loading/navigation state remains independent.
- Use `\.isCapturingSnapshot` only to freeze motion at a deterministic phase. The exception is content no settle window can stabilize: externally loaded substrates or wall-clock controls/timers may use an identical-layout placeholder.
  Otherwise never change layout, content, or behavior. Preserve the hybrid SwiftUI environment/trait-bridge accessor and mirrored setter in `SnapshotCaptureFlag.swift`; a plain `@Entry` breaks it.
- Use full-content frames for `ScrollView`, `List`, `Form`, and equivalent UIKit scrollers.
  Device presets retain viewport height as a minimum; custom frames shrink-wrap unless given a minimum.
  Include production navigation, tab, sheet, search, and toolbar chrome when measurement converges. For intentionally bounded/greedy containers, capture the shared scrolling child without adding snapshot-only layout.
  Fixed device frames are for non-scrolling subjects. Explicit `Frame.viewport` adaptive-shell captures require full-content pane coverage.
- Preserve frame names when changing traits. Presets carry truthful traits; component frames inherit.
  Explicit configuration traits override frame traits and retain identifier tokens; otherwise previews and captures use measured frame traits.
- Use `.retained` scene policy only for subjects requiring native scene chrome. Preserve traits, configured insets, and full-content sizing.
  Retention leaves identifiers unchanged, so name variants when both policies occur in a matrix. Previews do not establish retained-scene fidelity.
- Source Duo frames from native measurements; re-measure after runtime-pin changes and update README provenance. Synthetic frames do not change native pose or bar arrangement.
  Each new adaptive configuration needs its own case/model and matching readiness hooks.
- Keep ordinary profiles in `SnapshotConfiguration.DeviceProfile`, deriving dimensions from simulator display profiles.
  Distinguish authored insets/traits from measurements and preserve identifiers. Guard: `SnapshotDeviceProfileTests`.
  Share synthetic pose geometry and localized labels through `DuoPose`; keep production geometry adapters in consumers.
- Use two-axis full-content frames only for spatial canvases. Keep ordinary screen presets fixed-width. Guard: `SnapshotConfigurationTests`.
- Pixel stability can still show a loading placeholder. Seed final content or await completion through `prepareForCapture` before settling. Keep `onReadyToSnapshot` for actions that need settled UI; height-changing work must complete through `onReadyToMeasure` before sizing.
  A longer delay is not evidence of readiness.
- Measurement readiness does not replace final capture settling. Keep `.sameAsCapture` if async work can change height, or await it in `onReadyToMeasure` and use a `.settled` probe.
  Use `.immediate` only for synchronous final height. Measurement hooks apply only to intrinsic/full-content sizing. Guards: `AsyncContentCaptureTests`, `LargeViewCaptureTests`.

## Component comparisons and reference groups

- Consumers own theme identities and ordering; accept generic labeled panels and validated groups.
- Use `SnapshotCase.cutsheet` and `SnapshotPanelBuilder` for independent panels with fresh fixture state per invocation.
  Reject empty sheets and duplicate identities; keep single-view/cutsheet construction mutually exclusive and raw descriptors behind `Capture` SPI.
- Previews must use the same stored subject as captures, at normal panel width with horizontal scrolling for wide sheets.
- Preserve filenames and configuration identifiers. Structured case identity must prevent group/case-punctuation collisions.
- [SnapshotKitTesting](../SnapshotKitTesting/AGENTS.md) owns capture geometry, metadata, and per-panel comparison. Previews remain an approximation.

## Testing

`SnapshotKitTests` checks matrix combinations and identifier omission as pure values. Consumer image bundles exercise rendering through SnapshotKitTesting.
