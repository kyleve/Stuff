# StuffCore

StuffCore holds small, non-UI foundations shared by multiple Stuff apps.

Its first shipping facility is binary credential storage:

- `CredentialKey` gives every Keychain account a typed identity.
- `CredentialStore` is the injectable read/write/remove boundary.
- `SystemCredentialStore(service:)` stores generic-password items in the system
  Keychain.
- `InMemoryCredentialStore` is available through `@_spi(Testing)` in DEBUG
  builds for hermetic tests and previews.

The store accepts `Data`; callers own token/string encoding and empty-value
semantics. Add shared types under [`Sources/`](Sources/) and wire consumers in
[`Package.swift`](../../Package.swift). Run tests with `./test StuffCoreTests`.
