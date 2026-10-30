# ViewDocumentCore

See the [ViewDocument guide](../README.md) for composition, validation, and the wire format. This target is declared in the root Package.swift.

Validation also bounds modifier nesting and total modifier work. Standard limits allow 32 modifiers per node and 1,024 per document.

Scale amplification is limited to 1,000 along each tree path, including all animation poses. Smaller scales do not restore this conservative budget. Sibling branches have separate scale budgets.

Authored frame, padding, spacing, offset, and effect lengths share a 100-million-point budget after amplification. This rejects combinations that exceed native rendering precision. It is a conservative input budget, not a measurement of the final SwiftUI layout. Hosts still own measured layout and font metrics.

`ViewArtworkPlacement` validates host-relative artwork independently of the view tree. Call `validate()` before accepting it and `geometry(in:rightToLeft:)` during layout.
Its `Extent` and `Frame` values use portable point coordinates. The host converts them to its rendering framework and enforces paint clipping.
