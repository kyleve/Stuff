---
name: building-ui
description: Build and review this repository SwiftUI and UIKit surfaces. Use its layering, reuse, Broadway design-system, layout, accessibility, localization, preview, and image-snapshot conventions. Use when you create or change a view, screen, component, widget, app-extension UI, stylesheet, visual token, animation, UIKit bridge, preview, SnapshotProviding matrix, or UI snapshot reference. Use when you review UI code or rendered output.
---

# Building UI

Build repository UI through the existing model, design-system, and rendering
seams. Treat this skill as the repository-specific authority when generic
SwiftUI guidance conflicts with it. For example, use a Broadway stylesheet,
not a generic constants enum. Use `swiftui-pro` alongside this skill for
current SwiftUI API, performance, and platform guidance.

## Start from the existing shape

1. Read the root [`AGENTS.md`](../../../AGENTS.md), then every `AGENTS.md` that
   scopes the files being changed. Local files retain module-specific product,
   dependency, and lifetime invariants.
2. Inspect the feature's existing views, view models, reusable components,
   Broadway root, stylesheet, preview fixtures, and snapshot declarations
   before designing another path.
   Check supported themes and their local surface rules before choosing materials.
   For Where, follow the [theme rules](../../../Where/WhereUI/AGENTS.md).
3. Extend an existing view with a mode or shared subview when two surfaces
   express the same concept. Keep screen-specific registration and rendering
   declarations beside the represented screen.
   In-app examples and theme previews must reuse the production presentation component.
   If embedding needs a different size or interaction policy, add that input at the shared boundary.
4. Identify the narrowest layer that owns the behavior before editing UI.

## Keep views presentational

- Put persistence, domain rules, detection, aggregation, cache policy, and side
  effects in Core/services. Put observable mirrors, lifecycle orchestration,
  and intent methods in a view model. Let a `View` render state and route
  intents.
- Extract an `@Observable` model or focused child type when a view begins to
  own system logic, an internal state machine, or unrelated behavioral areas.
- Model mutually dependent UI values as one enum or named value so invalid
  combinations cannot be represented.
- Bind directly to observable state. For a derived binding, expose a computed
  get/set property on the model and bind to it. Do not build
  `Binding(get:set:)` in a view.
- Keep previews and tests on the production data flow. Inject a protocol fake
  or production-shaped fixture instead of adding DEBUG state or a parallel
  refresh path to product code.
- Scope presentation-driven work to actual visibility. Key tasks by every
  identity-relevant input and let cancellation return before changing durable
  presentation state, emitting haptics, or publishing late UI updates.

## Build appearance through Broadway

For this work, read [broadway guidance](references/broadway.md).

## Blend subtle card outlines with their surroundings

For this work, read [broadway guidance](references/broadway.md).

## Build with Liquid Glass

For this work, read [glass guidance](references/glass.md).

## Make layout adaptive

For this work, read [layout guidance](references/layout.md).

## Build for accessibility and localization

For this work, read [accessibility guidance](references/accessibility.md).

## Keep UIKit bridges focused

For this work, read [uikit guidance](references/uikit.md).

## Author previews and image coverage with the view

For this work, read [previews guidance](references/previews.md).
