---
name: building-ui
description: Build or review Stuff's SwiftUI/UIKit views, styles, previews, and snapshots using repository conventions.
---

# Building UI

Repository UI contracts take precedence over generic SwiftUI advice.
Use `swiftui-pro` when a task needs additional API, performance, or platform guidance.

## Repository boundaries

- Core/services own domain behavior and side effects; observable models own lifecycle and intents; views render and route intents.
- Extend the production presentation component for in-app examples and theme previews. Keep screen registration and rendering declarations beside the screen.
- Expose derived bindings as model get/set properties. Do not construct `Binding(get:set:)` in views.
- Previews and tests use protocol fakes or production-shaped fixtures, not DEBUG state or parallel refresh paths in product code.
- Presentation work follows visibility. Key tasks by identity-relevant inputs; cancelled work must not publish late state, durable changes, or haptics.

## Required task references

Read only the references for the affected behavior, including review work.

| Task | Required reference |
| --- | --- |
| Authored appearance, stylesheets, or subtle card outlines | [Broadway](references/broadway.md) |
| Liquid Glass | [Glass](references/glass.md) |
| Adaptive layout | [Layout](references/layout.md) |
| Accessibility or localization | [Accessibility](references/accessibility.md) |
| UIKit bridges | [UIKit](references/uikit.md) |
| Previews or image coverage | [Previews](references/previews.md) |

Module instructions own product-specific theme and coverage rules. For Where, use the [shared presentation contracts](../../../Where/WhereUI/Sources/Shared/AGENTS.md).
