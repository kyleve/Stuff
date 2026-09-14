# PortholeRemote

PortholeRemote owns native TLS transport, pairing, and executor clients. Read
[README.md](README.md), the [group contract](../AGENTS.md), and the repository
[contract](../../../AGENTS.md).

- Keep UI, providers, and application adapters outside this module.
- Use PortholeCertificates for certificate construction and parsing; never import X509 across its dynamic ownership boundary.
- Require pinned TLS 1.3 and an enrolled client certificate for operational connections.
- Keep enrollment on a separate temporary listener with a single-use token.
- Persist trust before publishing it; remove trust before closing revoked sessions.
- Forward invocation identities and scope generations without reconstruction.
- Keep observation sampling in the shared runtime and stream buffers bounded to the latest unread value.
- Bind remote observation references to their authenticated connection and stop them when that connection ends.
- Preserve task-local observation ownership through dispatch and invoke the native owner teardown protocol on disconnect.
- Keep one receive task per connection, at most one buffered request, and sequential dispatch.
- Close observation ownership on EOF without waiting for suspended native code; reject buffered requests after closure.
- Require custom runtime executor wrappers to forward `PortholeObservationOwning`.
- Never expose an approval RPC or retry an uncertain invocation automatically.
- Keep identities and invitations out of debugger values, generated exports, and logs.
- Test protocol behavior through production interfaces and TLS through loopback connections.
