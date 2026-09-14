# PortholeCertificates

This package creates self-signed P-256 certificates and checks their validity intervals.
Its public API uses Foundation data. X509 types stay inside the library.
PortholeRemote owns certificate pins, Keychain storage, and TLS authentication.

Use `PortholeCertificates.generate(name:at:)` to create certificate DER and private-key bytes.
Store private-key bytes only in native credential storage. Never export them to debugger values.
`isValid(certificateDER:at:)` checks encoding and dates. It does not establish trust.

The explicit dynamic product creates one ownership boundary for X509 and Swift Crypto.
The pinned Xcode compiler otherwise promotes Crypto into a target while linking an empty product wrapper.
That graph fails with `Crypto_17A3B1FFC41E47_PackageProduct` missing its binary.
Do not import X509 or link its product from application package targets.

The package manifest pins its dependencies. Tests check certificate validity and malformed data.
The Remote test suite checks the resulting identity through Security and TLS loopback connections.
