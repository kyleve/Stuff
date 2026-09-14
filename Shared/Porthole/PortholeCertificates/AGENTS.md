# PortholeCertificates

This package owns certificate creation and parsing. Read [README.md](README.md),
the [group contract](../AGENTS.md), and the [repository contract](../../../AGENTS.md).

- Keep this explicit dynamic package boundary until the pinned compiler can link the shared application graph without an empty Crypto product wrapper.
- Keep X509 types private to this module. Expose only opaque certificate and key bytes.
- Keep Keychain, network transport, debugger types, and application code outside this package.
- Treat key bytes as credentials. Never log or export them.
- Keep dependency versions in this package manifest aligned with the application resolution.
- Test generated certificates here and Security/TLS integration in PortholeRemote through `./test --porthole-host`.
