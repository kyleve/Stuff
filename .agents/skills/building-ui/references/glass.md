# UI guidance: glass

## Build with Liquid Glass

Apply these rules only when the resolved component style uses glass.

- Put related glass effects in one nearest `GlassEffectContainer` only when
  they must blend or morph.
- Give independently moving glass surfaces separate containers when the
  surfaces must cross with distinct z-order.
- Treat a glass container's `spacing` as its blend threshold, not as layout.
  Keep this value at or below the layout gap unless effects must merge at rest.
- Apply `glassEffect` after the modifiers that define its captured appearance.
  Put exact opaque content above a clear glass background layer.
- Use one `Shape` for glass, final clipping, content hit testing, and matched
  transitions.
- Disable hit testing on decorative material overlays.
- Use interactive glass only for controls.
- If glass supplies press feedback, use a plain button style.
  Cover the visible surface with `contentShape`.
- Reserve `glassEffectID` for insertion and removal morphs.
- If an authored layout owns a stable collection reorder, use
  `.glassEffectTransition(.identity)`.
- Treat Liquid Glass as a separate render layer. `geometryGroup` and
  `compositingGroup` do not preserve its identity across hierarchy changes.
- Keep the settled source order equal to the visual and accessibility order.
  Do not leave a reordered collection on permanent offsets.
- Keep a crossing collection's hierarchy stable until the motion ends.
  Commit its real source order without animation at the same visual endpoint.
- Preview reusable glass views inside their production container.
- Exercise each transition twice on a supported runtime. Static snapshots show
  only the settled state.
- Inspect Reduce Motion, edge taps, VoiceOver order, and focus.

API reference: [Apple's custom-glass guidance](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).
