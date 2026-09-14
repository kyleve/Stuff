# WhereAssets

This Foundation-only module owns the icon-preview resource bundle. Read its
[README](README.md) and the repository [contract](../../AGENTS.md).

- Keep the catalog at its existing `WhereUI/Sources/Resources/AppIconPreviews.xcassets` path and use `./icons` to change it.
- Keep string catalogs out of this target; Xcode's private resource helpers collide under Porthole instrumentation.
- Select source and resource paths explicitly when using the shared `Where` target path.
- Do not import WhereUI, persistence, UI frameworks, or application services.
- Install generated bindings through WhereUI's existing composition hook.
- Keep resource ownership tests in `Tests/WhereAssetsTests.swift`.
