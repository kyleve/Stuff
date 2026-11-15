# UI guidance: broadway

## Build appearance through Broadway

Before adding dependencies, read the root static-linking tripwire. If a
consumer already receives Broadway through another product, use that product's
exported root seam and do not link `BroadwayCore` or `BroadwayUI` again.

For a module that owns a design language:

1. Define one `BStylesheet` with a deterministic `static let default` for
   off-tree layout helpers, tests, and rootless fallbacks.
2. Resolve the active sheet from `bContext` through a typed
   `EnvironmentValues` property. Views read it with `@Environment`.
3. Seed `broadwayRoot(themes:)` at the composition root. Export a module root
   helper when downstream targets must seed the same context without importing
   Broadway directly. A self-contained public tool can seed its own root so it
   renders correctly inside or outside a host app.
4. Keep fixed values in property defaults or `standard` values. Derive only the
   trait-reactive slice in `init(context:)`, starting from those defaults.
5. Test default values, trait derivation, environment resolution, and every
   exported root path.

When a module separates theme definitions from its base stylesheet:

- Follow the module's documented order for base defaults, trait resolution, and theme overrides.
- Keep theme values and theme-specific trait decisions in the definition. Keep application limited to assigning resolved fields.
- Use `BModeVarying` for paired light/dark values, selected with the slice's explicit mode.
- Test inheritance, explicit zero overrides, and preservation of unrelated component state.
- For Where's concrete contract, follow the [module theme rules](../../../../Where/WhereUI/AGENTS.md).

Organize tokens by ownership:

- Put geometry, fonts, colors, shadows, motion, and other authored appearance
  on the owning component's nested style struct. Nest subparts when a group
  grows. Do not grow a flat stylesheet or flat component style.
- Use shared spacing, size, palette, typography, or motion scales only when a
  token is genuinely cross-component. Do not borrow another component's style.
- Model a visual axis as a typed `Variant` and resolve one complete style with a
  subscript or resolver before rendering. Avoid scattering conditional token
  reads through `body`.
- Give a reusable rendering primitive an appearance/style input. Let the
  parent component's style own product meanings such as watermark or stamp.
- Keep live-container, content, or measured-chrome geometry in the layout/view
  layer. A stylesheet cannot resolve a value that exists only after layout.
- Leave adaptive system roles such as `.secondary` and `.accentColor` inline
  when they are semantic rather than authored design tokens.

Resolve appearance from `SlicingContext.traits` before rendering. This covers
Dynamic Type, color scheme, Reduce Motion, Reduce Transparency, and
Differentiate Without Color. Resolve each component's layout policy, spacing,
alignment, copy length, and motion together. Do not export a global raw trait
flag such as `isAccessibilitySize` for views to interpret again.

For example:

```swift
// Before: the view interprets a system trait.
@Environment(\.dynamicTypeSize) private var dynamicTypeSize
// body: if dynamicTypeSize.isAccessibilitySize { ... }

// After: the slice resolves a component policy.
// WhereStylesheet.init(context:)
if context.traits.contentSizeCategory.isAccessibilitySize {
    locationForecast.header.layout = .stacked
}
// View: if stylesheet.locationForecast.header.layout == .stacked { ... }
```

Keep rendering types out of stored tokens when they cannot be `Equatable`.
Store an `Equatable` descriptor and construct `AnyLayout` or `AnyTransition`
from it. That type constraint does not justify reading traits in a view.

For authored dimensions, use system font metrics with the slice's explicit
content-size category. Do not resolve against ambient UIKit traits. Use
`@ScaledMetric` in production only when a required input is unavailable during
slicing. Document that input at the declaration. Keep semantic fonts intact.

Keep actual content fit, measured chrome, and container geometry in views or
layout helpers. Preserve `ViewThatFits`. Keep capture-time motion in the shared
static-motion helper. User-controlled preview state and live designer drafts
remain runtime inputs that compose over resolved base styles.

Resolve styles beneath the Broadway root that supplies their traits. For
styled subtrees, pair scoped SwiftUI appearance overrides with Broadway trait
overrides. Preserve the same category limits and color mode in both systems.

Before finishing a UI change:

1. Search changed views for `dynamicTypeSize`, `sizeCategory`, `@ScaledMetric`,
   color scheme, size classes, and accessibility environment reads.
2. Move decisions supported by slicing inputs into the owning component style.
3. Document each remaining direct read at its declaration. Name the required input unavailable during slicing.
   Infrastructure that bridges system traits and snapshot configuration can read them directly.
4. Test the standard/accessibility boundary, trait updates, scoped overrides,
   and affected rendered states. Compare scaled geometry with system metrics.

These repository rules override generic SwiftUI skill advice about direct
trait reads and `@ScaledMetric`. Do not modify downloaded external skills.

See the WhereUI [design-system guide](../../../../Where/WhereUI/README.md#design-system)
for the fullest production example and PeriscopeTools/Flyover for smaller
module-owned stylesheets.

## Blend subtle card outlines with their surroundings

- For subtle outlines that separate glass or matte cards from their background, place the
  entire stroke outside the surface. Apply it after clipping the fill and
  artwork so the stroke remains visible without changing layout or hit bounds.
- Use a translucent stroke color so the surrounding background shows through.
  For a neutral dark outline, use black with low opacity instead of solid gray.
  Keep color, opacity, and width in the owning stylesheet; preserve required contrast.
- In SwiftUI, `strokeBorder` draws inward and `stroke` straddles the edge.
  To draw fully outside an insettable shape, use
  `shape.inset(by: -width).strokeBorder(color, lineWidth: width)`.
- Check the outline against the actual surrounding colors in each supported theme and
  light/dark appearances. Inspect corners and clipping as well as straight edges.
