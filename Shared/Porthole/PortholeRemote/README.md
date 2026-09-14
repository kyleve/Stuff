# PortholeRemote

PortholeRemote connects native clients to an application's Porthole executor.
It supports iOS and macOS through Foundation, Network, Security, and PortholeCertificates.
The package manifest pins the certificate library.

## Start a listener

Create one `PortholeRemoteKeychain` at the application composition root.
Load its `identity(name:at:)` and create a `PortholePeerTrust` with that Keychain.
Construct `PortholeRemoteDispatcher` with the shared executor and an application descriptor provider.
Pass these dependencies to `PortholeRemoteServer`.

Call `start()` only after the user enables remote access.
Call `stop()` when the user disables access or the owning application runtime ends.
The listener does not activate when Porthole opens locally.

Call `beginEnrollment()` to show a QR code or copyable invitation.
The invitation contains a 256-bit random token and a server certificate pin.
Treat the encoded invitation as a credential.
It expires after two minutes and can enroll one client.

The host needs a local-network usage description and these Bonjour service declarations:

- `_porthole._tcp`
- `_porthole-pair._tcp`

## Connect a client

`PortholeDiscovery.applications()` publishes nearby service names.
Discovery does not grant access.
`PortholeRemotePairing.enroll` exchanges an invitation for a paired server record.
Store that record with `PortholeRemoteKeychain.save(server:)`.
Connect with the client's identity and the stored server pin.

`PortholeRemoteClient` conforms to `PortholeExecuting`.
Use `application()` to obtain current scope generations.
Use `capabilities(in:)` to discover APIs and their parameter schemas.
It loads the catalog in pages. Use `capabilityPage(in:offset:limit:)` to request one page directly.
Use `invoke(_:)` for inspection, files, source, screenshots, logs, persistence, and lifecycle capabilities registered by the host.
Paging uses each capability's advertised parameters.
`observations(of:interval:)` starts a shared runtime observation of a classified read.
The runtime owns the sample schedule and assigns each sample a new operation ID.
The stream retains only the latest unread value. Sequence gaps do not represent recorded history.
Ending the stream stops its runtime observation after the current bounded read finishes.
Client requests use a bounded queue on one connection. Closing the client closes that connection and ends its observations.

## Authorization and lifetimes

The operational listener requires TLS 1.3, a client certificate, and an enrolled certificate pin.
The client checks the server certificate pin and certificate validity.
The temporary enrollment listener uses pinned TLS 1.3 without client authentication.
It accepts enrollment messages only and closes after successful enrollment, cancellation, or expiry.

Private keys and peer records use device-only Keychain items.
The host supplies an access group when signed applications share identities.
Do not export this module's credentials through generated bindings or diagnostic capabilities.
`revoke(peerID:)` removes trust before it cancels that peer's active sessions.

All invocations pass through the host executor.
An approval response contains the exact pending proposal.
No remote operation can approve it.
After the device approves the proposal, the client can resubmit that exact invocation.
The runtime journal determines whether it executes or returns an existing result.
Scope replacement invalidates old invocations and object references.
Each authenticated connection owns the observation references that it starts.
Other connections cannot read or stop those references through the remote lifecycle controls.
The server records an observation identity before it starts the operation.
Disconnect, revocation, and listener shutdown stop those observations even when a start reply was lost.
One receive task detects disconnect while a native call is suspended.
Disconnect requests cancellation and closes observation ownership before that call returns.
Native cancellation does not force Swift code to stop or reverse its effects.
The session supplies native observation ownership through task-local context.
The shared runtime uses that ownership to stop nested observations when the connection ends.
Custom executor wrappers must forward `PortholeObservationOwning` to the runtime.
Custom adapters across detached tasks or C callbacks must preserve that execution ownership before they call nested observation APIs.

Transport failures never cause automatic retries.
A failed or cancelled call may already have changed live state.
Frames have a four-megabyte limit; listener startup, handshake, and frame transfers have 30-second deadlines.
Authenticated connections can remain idle.
The server accepts at most eight concurrent connections.
Each connection dispatches requests in order and buffers at most one complete request.
The receiver can read one further frame while dispatch runs. Queue overflow closes the connection.
Buffered requests cannot execute after the session closes.

## MCP and command line

The `porthole` executable supports discovery, pairing, inspection, invocation, read observations, and MCP over standard input and output.
Run `swift run porthole --help` for argument syntax.
Pairing reads its token from standard input to keep it out of command history.

`PortholeMCPServer` implements the [MCP stdio transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
and the initialization handshake for protocol version `2025-11-25`.
Its three tools expose the application descriptor, capability catalog, and shared executor.
The catalog tool requires an offset and a limit from 1 to 200.
Its result includes the offset, total count, and page items.
The CLI processes MCP requests in order.
It does not advertise optional MCP resources, prompts, or task execution.

## Tests

Run `./test PortholeRemoteTests`.
Tests exercise local TLS handshakes, token expiry and reuse, revocation, framing limits, exact approval proposals, stale scopes, and uncertain replies.
Network tests use loopback listeners and generated test identities.
They do not enroll external applications or change a user's credentials.
