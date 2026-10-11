# KeychainKit

KeychainKit provides a focused, injectable wrapper around generic-password
items in Apple Keychain Services. `SystemKeychainStore` stores opaque `Data`
under an explicit service/account pair and supports typed accessibility and
iCloud Keychain synchronization policy; `KeychainStore` lets consumers use an
in-memory implementation in tests. `create(_:)` inserts without replacing an
existing local item. It is not a distributed lock between devices.
`write(_:)` inserts or updates an item.

`KeychainCollection` and `SystemKeychainCollection` provide append-only storage
under typed `KeychainAccount` identifiers. Give independent secrets different
accounts so eventual iCloud synchronization can retain all of them. Consumers
can use `InMemoryKeychainCollection` through the testing SPI.

The module deliberately does not generate, parse, or rotate secrets. Product
modules own those rules and must distinguish `nil` (the item does not exist)
from a thrown `KeychainError`, including `errSecInteractionNotAllowed` while
protected data is unavailable.
