# ImageDiffKit

ImageDiffKit is the shipping, UI-free image comparison engine shared by
Patchlight and the repository's snapshot-test reporting pipeline.

`ImageDiffEngine` accepts two image `Data` values, decodes them with ImageIO,
normalizes them through CoreGraphics into one 8-bit premultiplied RGBA layout,
and returns either:

- comparable metrics (dimensions, changed pixels/fraction, maximum channel
  delta, and the tight changed bounds), plus an optional locally generated PNG
  heatmap; or
- an explicit dimension mismatch, for comparison modes that cannot be applied
  honestly.

No network, UI, tolerance policy, or test framework belongs here. Consumers
choose `ImageDiffOptions` and interpret the result. Run tests with
`./test ImageDiffKitTests`.
