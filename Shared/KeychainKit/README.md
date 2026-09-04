# KeychainKit

KeychainKit provides a focused, injectable wrapper around generic-password
items in Apple Keychain Services. `SystemKeychainStore` stores opaque `Data`
under an explicit service/account pair and supports typed accessibility and
iCloud Keychain synchronization policy; `KeychainStore` lets consumers use an
in-memory implementation in tests. Use `create(_:)` when a caller must never
overwrite a concurrently synchronized value; `write(_:)` provides normal
upsert behavior.

The module deliberately does not generate, parse, or rotate secrets. Product
modules own those rules and must distinguish `nil` (the item does not exist)
from a thrown `KeychainError`, including `errSecInteractionNotAllowed` while
protected data is unavailable.
