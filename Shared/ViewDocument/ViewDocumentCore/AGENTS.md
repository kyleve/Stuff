# ViewDocumentCore

ViewDocumentCore follows the [group contract](../AGENTS.md) and [repository rules](../../../AGENTS.md). See [README.md](README.md).

Keep source tests one-to-one. Run `./test ViewDocumentCoreTests`.

Validate modifier nesting, aggregate modifier counts, cumulative scale amplification, and amplified authored geometry before rendering wire input. Include every animation pose in the scale budget. Keep authored geometry costs separate from host layout measurement.

Validate artwork placement before hosting it. Keep paint outsets finite and separate from layout bounds. Hosts must clip transformed artwork to those paint bounds.

Keep semantic opacity and color blends finite and depth-bounded. Do not resolve them to captured RGB values. Guard: `ViewColorDescriptorTests`.
Keep native palette colors symbolic and background levels host-supplied. Guard: `ViewDocumentAppearanceTests` in ViewDocumentUI.
