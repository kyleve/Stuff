# CQuickJS

Vendored QuickJS-NG core and a narrow C bridge. See [README.md](README.md) and the
repository [contract](../../../AGENTS.md).

- Keep upstream files byte-identical to the revision in VENDOR.json.
- Keep host filesystem, process, network, and module-loading APIs absent.
- Expose opaque ownership through the public header; do not expose JSValue to Swift.
- Keep native promise values alive until completion or runtime destruction.
- Exercise the C bridge through PortholeJavaScriptTests.
