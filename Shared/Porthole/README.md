# Porthole

Porthole provides reusable debugger modules for application adoption. The
[native package](Package.swift) builds the runtime, JavaScript console, AI
providers, repository tools, authenticated transport, and command-line client.
It also qualifies shared UI models on native macOS.

The [core](PortholeCore/README.md) defines typed capabilities, contexts, evidence,
and scoped object references. The [runtime](PortholeRuntime/README.md) enforces
scope validity and action approval for every client. Hosts inject their existing
services and register compiled handlers at the application composition root.

The console uses a bounded QuickJS interpreter. Its native calls use the shared
execution boundary. Provider credentials remain in native stores. AI sessions
preserve tool evidence, and repository publication requires explicit native review.
The remote client uses certificate pins and mutual TLS.

The [UI module](PortholeUI/README.md) documents its presentation and integration
APIs. Application adoption, generated bindings, and application test targets are
separate work. This package does not wire Porthole into Where. Its native UI
target excludes the UIKit, Broadway, and SnapshotKit dependencies that iOS hosts
must supply.

## Native validation

From the repository root, run:

```sh
swift test --package-path Shared/Porthole
swift test --package-path Shared/Porthole/PortholeCertificates
```

The second command covers the separate dynamic certificate package. The package
manifests and lockfiles define the toolchain requirements and dependency pins.
Protocol fakes and loopback connections keep native tests independent of live
model providers and GitHub accounts.

For command syntax, run:

```sh
swift run --package-path Shared/Porthole porthole --help
```

The [CLI module](PortholeCLI/README.md) describes pairing and MCP usage. A host
application must explicitly activate its listener before a client can connect.
The [QuickJS vendor record](CQuickJS/VENDOR.json) identifies the bundled sources
and their [license](CQuickJS/LICENSE).
