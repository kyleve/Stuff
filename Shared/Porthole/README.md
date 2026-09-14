# Porthole

See [acceptance measurements](ACCEPTANCE.md) for disabled composition checks and repeatable bundle, launch, and memory reporting.

Porthole connects a running application's source, state, and operations to a
human debugger and an AI investigation workspace. Local and remote clients use
the same scoped execution and approval boundary.

The application creates one runtime and injects its existing services. Enabling
the workspace does not open another application store. Generated bindings remain
ordinary compiled Swift; JavaScript orchestrates those bindings.

## Use in Where

Enable Porthole in Settings under Privacy and Diagnostics. Open the floating
developer menu, then select Porthole. The menu captures the underlying screen
before it covers the app. A drift issue preserves its selected issue and day.
An application-wide origin works when no screen has registered a context.

Explore shows compiled APIs, source, scoped objects, and related contexts. Select
an API to inspect its signature and fill its argument form. Stored-value reads
run immediately. Computed getters, unknown effects, and live changes require
review. Unsupported declarations show their specific limitation.

Callable APIs classified as reads also offer **Watch every second** in the
argument form. A watch keeps the selected receiver and arguments fixed. Its
latest sample opens through the same evidence controls as a normal call.
**Stop watching**, leaving the form, or closing Porthole stops the watch.
An unconfirmed stop remains visible and retryable. The watch does not record
earlier values.

The console runs JavaScript against bundled capabilities. Stop interrupts the
interpreter and requests cancellation of native calls. It cannot undo a native
operation that already changed state.

In Ask, choose OpenAI or Anthropic and enter an API key. Approve diagnostic
sharing for that provider before starting an investigation. Saved conversations
retain their original evidence. Continue with the current app context explicitly
after a relaunch or scope replacement. Old object handles remain expired.

For a flight investigation, start from the issue and inspect its selected day,
current inputs, attribution, settings, and dismissal state. Search the bundled
detector source and replay the copied input through the ordinary detector APIs.
A replay demonstrates current behavior; it does not prove what an earlier,
unrecorded execution did.

Fix opens an isolated repository workspace. Configure the public client ID of
the registered GitHub App, sign in with its device code, and select repository
files. The [GitHub setup](PortholeGitHub/README.md#where-registration) lists the public
client ID for the Stuff-only installation. Device authorization remains a separate step. Edits use a fixed fetched commit. The installed source is separate evidence,
including local build changes. Review the patch, proposed tests, description,
and validation state before creating a draft pull request. Use synthetic test
data by default. Personal diagnostic evidence requires a separate selection.
Swift changes take effect in a subsequent app build.

Remote access has its own activation control. Enroll the Porthole Mac Catalyst
app or CLI with the short-lived QR/paste invitation. Paired connections use
certificate pins and mutual TLS. Revoking a client closes its active sessions.
The [remote module](PortholeRemote/README.md) documents CLI and MCP usage.

## Build and distribution boundaries

Where and its extensions link the explicit dynamic `WhereApplicationSupport` product.
The product contains the existing application modules and their dependencies in one shared image.
The Swift modules, source imports, and runtime activation remain separate.
This packaging avoids a static copy of generated bindings and debugger services in each extension executable.
The compiler and bundle checks must verify shared linkage, resource loading, and unchanged App Intents metadata.

The exporter inventories every first-party module in Where's process graph.
Application modules receive compiled bindings. Porthole's own execution and
approval machinery has source-only, non-callable entries. Credential files and
third-party internals have explicit exclusion records. See the
[generator contract](PortholeGenerator/README.md) for supported signatures and
the normal-source compiler guard.

All-build availability is the product target. The console calls bundled
capabilities; source fixes go through pull requests and new builds. Apple's
[App Review guidelines](https://developer.apple.com/app-store/review/guidelines/)
remain an external distribution requirement. Compiler tests do not establish
App Review acceptance.

The [acceptance procedure](ACCEPTANCE.md) records bundle, launch, and memory
measurements and keeps missing physical-device evidence explicit.

Module documentation describes the runtime, exporter, console, providers,
repository workspace, and presentation APIs. The implementation follows the
approved on-device Porthole plan and retains the remote tooling concepts from
[PR #131](https://github.com/kyleve/Stuff/pull/131).

The local [runtime package](Package.swift) reuses these modules' source and test
directories. It builds the core, runtime, console, agent, repository tools,
transport, and CLI without application dependencies. It also qualifies the UI
models through the native macOS SwiftUI surface. Use `./test --porthole-host`
from the repository root. The application graph remains in the root package
and project manifests. iOS rendering and generated application bindings use
the iOS test schemes.
