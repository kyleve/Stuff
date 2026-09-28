# KeychainKit – Module Shape

KeychainKit is the small cross-app Keychain boundary: generic-password storage
for opaque `Data`, with typed accessibility and iCloud-synchronization policy.
It depends only on Foundation and Security and never assigns product meaning to
service/account identifiers. See [`README.md`](README.md) and the root
[`AGENTS.md`](../../AGENTS.md).

Keep the protocol injectable, keep raw `OSStatus` failures observable, and do
not turn an inaccessible item into `notFound`; callers decide whether absence
permits creating a new secret. Tests use the in-memory store SPI, never a
user's Keychain. Run `./test KeychainKitTests`.

Keep collection entries create-only. Do not treat a successful local insert
as a cross-device uniqueness guarantee (`KeychainCollectionTests`).
