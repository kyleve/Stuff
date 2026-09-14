# Porthole CLI

This native executable connects to an explicitly enabled Porthole listener.
It shares pairing, TLS, invocation, and MCP behavior with
[PortholeRemote](../PortholeRemote/README.md).

Run `swift run --package-path Shared/Porthole porthole --help` from the repository.
Run `swift run --package-path Shared/Porthole porthole pair`, then paste the invitation shown by the application.
Run `swift run --package-path Shared/Porthole porthole paired` to find its service name.

`application` prints current scopes as JSON.
Save one scope to a JSON file and pass that file to `capabilities`.
Save a complete invocation to a JSON file and pass it to `invoke` or `watch`.
`watch` accepts read capabilities only.
Live changes require approval on the device.
After approval, reuse the exact invocation file.

Configure an MCP client to launch `porthole mcp <service-name>`.
Standard output contains protocol messages only.
Pair the application before starting MCP.

The executable stores its identity and enrolled server pins in the native Keychain.
Command parsing and protocol behavior are tested in `PortholeRemoteTests`.
