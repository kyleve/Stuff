# UI guidance: layout

## Make layout adaptive

- Prefer semantic system APIs such as `defaultScrollAnchor`,
  `containerRelativeFrame`, safe-area APIs, and adaptive stacks before reaching
  for `GeometryReader`.
- When real chrome must be measured, use a focused preference or
  `onGeometryChange`. Compute expensive layout once into state rather than on
  every `body` pass.
- Use semantic fonts. Resolve authored dimension scaling in the stylesheet,
  subject to the documented runtime-input exception. If a glyph sits inside a
  fixed container, give it an intentional fixed font. If text scales, grow or
  restack the surrounding layout rather than truncate or squeeze it.
- Preserve navigation bars, toolbars, search, safe-area insets, and modal chrome
  when introducing custom containers or scroll behavior.
- Animate insertion/removal with a transition on each state branch plus an
  animation keyed to the state. Pair each `contentTransition` with an animation
  keyed to the displayed value. Hidden content must leave the tree rather
  than remain at zero opacity.
- Keep the visual structure consistent across states and variants unless the
  difference is intentional and modeled by the component style.
- Put large row trees behind small named `View` types before applying focus,
  reveal, or navigation wrappers. A computed `some View` property still exposes
  its underlying generic value to the enclosing body. Use nominal child views
  to bound copies. Keep measured size budgets local to the guarded surfaces.
  Guard: [FeatureGuidePageTests](../../../../Where/WhereUI/Tests/FeatureGuidePageTests.swift).
