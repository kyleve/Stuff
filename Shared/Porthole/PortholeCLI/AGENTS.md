# PortholeCLI

This executable is the native command-line entry for PortholeRemote. Read
[README.md](README.md) and the repository [contract](../../../AGENTS.md).

- Keep protocol, parsing, pairing, and transport behavior in PortholeRemote.
- Write only JSON-RPC messages to standard output during MCP sessions.
- Read enrollment credentials from standard input, never command arguments.
- Route live operations through the same remote executor and device approval boundary.
- Use the remote client's shared runtime observation lifecycle for `watch`; never poll the underlying capability independently.
- Keep the entry point thin; test reusable behavior in PortholeRemoteTests.
