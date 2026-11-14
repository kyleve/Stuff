# Developer and Flyover contracts

Read the [module contract](../../AGENTS.md) and the [repository contract](../../../../AGENTS.md) first.

- The DEBUG developer accordion may only update
  `WhereDeveloperLaunchController` for the next launch. Inspector and demo are
  mutually exclusive. It must not switch the current runtime. A demo request
  is consumed once before the onboarding gate and must never open a real store.
  Keep its synthetic clock scoped to the in-memory demo session.
- Keep the DEBUG Logs destination visible for every
  `WhereModel.logStoreState`. Opening, unavailable, and failed stores are
  diagnostics to render, not reasons to hide the tool.
- Keep the DEBUG card designer's draft in one root-owned `CardDesignerModel`.
  Persist the draft. Leave its app-wide override disabled at every launch.
- Flyover infrastructure stays under `#if DEBUG` in
  [`Sources/Developer/Flyover`](Flyover). Each represented
  screen declares a DEBUG-only `WhereFlyoverProviding` extension in its own
  source file. The integration may import the app-agnostic `Flyover` module
  and build one unactivated in-memory `WhereScope`. The shared module must
  never import WhereUI.
- Derive `WhereFlyoverScreenID` from the represented view type. Keep that
  screen's variants, viewport/navigation settings, and outgoing routes in its
  colocated registration. Never restore a centralized screen enum or catalog
  factory methods.
- Construct and retain the Where Flyover catalog once after its world loads.
  Never rebuild fixture state from a SwiftUI `body`.
- Build one `WhereFlyoverWorld` for each hosted web export. Reuse it for every
  capture. Never activate its scope or read user data.
- Export stable screen IDs from reflected screen and context type names. Use
  snapshot case names for snapshot-backed variant IDs.
- Present Where Flyover from the developer accordion with `fullScreenCover`.
  Place it outside the selected-tool `NavigationStack`.
- Register leaf screens against Flyover's default navigation container. Use
  `.none` only for views that own their root stack and for widgets/snippets.
