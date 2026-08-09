# ImageDiffKit – Module Shape

Shipping, UI-free image normalization and pixel comparison. See
[`README.md`](README.md) and the root [`AGENTS.md`](../../AGENTS.md).

Depend only on Foundation and Apple image/graphics frameworks. Keep comparison
deterministic and local; provider image analysis, review policy, rendering UI,
and test-framework verdicts belong to their consumers. A dimension mismatch is
a result, while decode/normalization/encoding failures throw typed errors.

Tests live in `ImageDiffKitTests` (`./test ImageDiffKitTests`).
