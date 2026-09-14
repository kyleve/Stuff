# PortholeUI

PortholeUI provides an opt-in debugger for an application-owned Porthole registry.
It contains a context explorer, source browser, generated call forms, JavaScript console, and operation review queue.
The optional agent surface adds provider setup, consent, and a saved investigation conversation.
`PortholeRemoteView` provides the Mac and iPad client for paired applications.
The host controls provide separate remote activation, enrollment invitations, and client revocation.

## Integration

Create one presentation controller at the application composition root:

```swift
let presentation = PortholePresentationController(
    registry: registry,
    applicationTitle: "Where"
)
```

Capture the selected screen before opening developer controls. Present its frozen context:

```swift
presentation.present(origin: .screen(context))
```

For an application-wide investigation, use `.application(scopeToken)`.
On iOS and Mac Catalyst, attach `.portholePresentationAnchor(controller: presentation)` once at the application root.
The anchor presents above existing sheets in its own window. It observes presentation changes even when a full-screen modal covers the SwiftUI root.
Do not add another sheet binding for the same controller.
Place the launch control inside application modals so it remains reachable above their native presentation.
Interactive dismissal and the Done button both close the captured session. A late dismissal cannot close a replacement session.
On native macOS, present `PortholeView(controller: presentation)` through the host's normal presentation container.
Register related contexts through `registerContexts(_:)`. Attach a configured agent model through `attachAgent(model:)`.
`configureAgent(storageURL:keychainService:context:)` creates the provider bridge after the host captures an origin.
Setup errors appear through `agentConfigurationError` in the Ask tab. Its retry action opens the saved investigation again without deleting data.
Keep the host runtime available after this method throws. Manual exploration and reopening do not depend on agent setup.

Create `PortholeRemotePresentationModel(keychain:clientName:)` for the remote client, then pass it to `PortholeRemoteView(model:)`.
The remote client keeps pairing credentials in its native Keychain. It reuses the generated call form through an injected executor.
After host approval, the form retries the exact pending invocation. Later field edits cannot change that approved request.

Create one `PortholeHostPresentationModel(executor:application:serviceName:keychainService:)` with the shared registry and application descriptor provider.
Attach it through `attachHost(model:)`. Its initializer neither reads credentials nor opens a listener.
The Remote tab starts these resources only after the user selects Enable remote access.
Call `await host.disable()` before invalidating its application scope. Closing the debugger sheet leaves the host's activation choice unchanged.
One-time invitations support QR scanning, selectable text, and system sharing. Revocation closes the client's active connections.

Attach `PortholeGitHubPresentationModel` through `attachGitHub(model:)` to show the Fix tab.
Its native review flow publishes an immutable proposal only after an explicit user action.
Alternatively, call `configureGitHub(storageURL:keychainService:clientID:installedBuildIdentity:isDirty:initialRepository:initialBranch:)` after capturing the presentation origin.
It creates one native GitHub client and persisted workspace, attaches the view, and registers scratch-workspace capabilities.
Repeated calls retain those resources and register each scope once. A late configuration cannot replace a newer presentation.
Configuration errors appear through `githubConfigurationError` and the Fix tab; manual debugging remains available.
An empty client ID shows setup for the public GitHub App ID. User credentials remain in Keychain.
The installed source remains evidence; repository edits use a separate immutable base and require the current workspace revision.
The source comparison shows installed-to-base differences without adding them to the patch.
Loading more files keeps the captured commit even when the target branch advances.
Use Refresh base from branch to move an empty workspace to the branch's current commit.
This action requires no saved patch, unsaved editor text, or pending publication. An unchanged base preserves its review and CI state.
An unpublished review states that compilation and tests have not run. Proposed tests remain visible in the patch diff.
CI results belong to the exact proposal fingerprint and published commit. New reviews clear old results; delayed responses cannot validate a replacement review.
Refreshing the same published review preserves its CI results.
An interrupted publication keeps its saved identity and locks edits until the same proposal is reconciled.
AI can load files, prepare edits, and save a review through the shared executor. Only the native review can publish it.
Regression evidence defaults to synthetic examples. A proposal declared personal requires a separate selection for that exact saved review.
The declaration does not detect personal data automatically. Inspect the full description and patch before publishing.

## Context and lifetime

The origin remains unchanged while the user navigates context links and breadcrumbs.
The host captures screen values, source locations, and scoped object references. The UI never opens a replacement application store.
Expired scopes reject live calls. Their frozen origin values remain readable until the presentation closes.
Temporary view rehosting preserves the current inspection. Attachment callers share one presentation-owned scope read; cancelling one caller does not cancel another reader.
Dismissal or explicit refresh cancels that owned operation. Delayed results must match both its operation and presentation.
A new presentation loads its scope again; explicit refresh and evidence retry actions query current state.
Recovery descriptions and buttons scroll at large text sizes. Snapshot readiness waits for the fixture's actual presentation or evidence model before measurement and capture.

Explore > All declarations and compilation coverage opens the complete module catalog, including modules with no active bindings.
Each module shows its build configuration, compiler identity, source count, and declaration counts by status.
Search matches declaration names, signatures, conditions, and unsupported reasons. Pages contain at most 50 rows and replace the previous page.
Rows separate actual installed status from planned adapter support. Inactive declarations have no call action, even when their plan is callable.
Declaration details show precise limitations and compilation conditions. Source links retain the original scope, file hash, and line.
The paired client uses the same coverage reads. Registered capability search also matches summaries and unsupported reasons.
A missing catalog produces an explicit error; it does not appear as complete coverage.

Generated forms use the capability schema for Boolean, integer, number, and string inputs. Complex values use validated JSON.
The receiver picker contains scoped object references. Static calls and constructors use no receiver.
Each form identifies unisolated, MainActor, actor-instance, or adapter-managed execution.

Typed evidence in explorer, call results, console results, and agent tool history opens the same inspectors.
Object links preserve the recorded scope generation. Opening one reads metadata without evaluating native properties.
Inactive result handles can also expire through bounded retention. Their recorded JSON remains evidence, but expired handles cannot bind to replacement objects.
The inspector lists candidate APIs and preselects the recorded receiver. The runtime still validates its type, scope, and approval.
Candidate matching uses generated type names; adapters and generic type names can require a search in Explore.

Source links preserve the file SHA-256, scope generation, and selected line. A mismatched archive cannot replace recorded evidence.
Complete saved source files remain readable after scope expiry when their content passes its hash check.
Frozen context values also remain readable. Related context links and live object handles require their original active scope.
Bare paths, identifiers, and prose do not become links. Malformed references show an error beside the original JSON.
The paired Mac and iPad client uses the same inspectors through its original connection.
Remote source reads use bounded pages and verify the reconstructed file hash. Missing host capabilities produce explicit errors.
Remote source inspection accepts at most 100,000 lines and 10 MB per file.
An old inspector cannot send calls through a replacement connection.
The focused relationship graph shows incoming and outgoing context links. Each node opens its recorded context without changing the investigation origin.

## Calls and approval

Forms and scripts call `PortholePresentationController.execute(_:)`.
This method suspends a local call when the registry requires approval. Review resumes the exact approved invocation.
The review queue also shows remote requests from the current scope. A remote client retries its original operation after approval.
Closing the presentation cancels local scripts and agent work, then rejects local requests that still await approval.
Cancellation cannot undo native work that already changed application state.

Callable operations classified as reads offer Watch in the invocation form. A watch freezes its receiver and arguments and samples once per second.
The runtime owns sampling. Local and remote forms use the same typed observation client to start, wait for results, and stop.
The form shows the latest value through its normal evidence controls. Sequence gaps are explicit; previous values are not recorded.
Stop and leaving the form request cancellation. A delayed result cannot replace the next watch or a newer scope.
If Stop cannot be confirmed, the form keeps the failure visible and permits another stop attempt. It does not start another watch.

Use `PortholeScreenshotEvidence` to preserve an image captured before developer controls open.
It refuses image replacement while Porthole is visible. Without a frozen image, it also refuses live capture during that presentation.
The native `PortholeWindowScreenshotCapture` stays in this module, outside automatic application API export.

The console supports top-level await:

```javascript
await porthole.call("porthole.discover", {
  arguments: { query: "flight", offset: 0, limit: 20 }
})
```

Pass an optional `receiver` reference beside `arguments` for an instance member.
The console records native calls and results as execution evidence. Provider credentials never enter its values.

## Appearance and validation

The public view seeds its own Broadway root on iOS and Mac Catalyst.
Broadway currently depends on UIKit. The macOS surface uses the same stylesheet tokens through SwiftUI environment values.
Developer-facing copy uses literal strings in every build configuration.

Swift Testing covers frozen origins, approval identity, cancellation, and typed input validation.
UIKit integration tests wait for appearance and transition conditions. They cover modal presentation, external dismissal, and replacement sessions.
SnapshotKit matrices cover captured context, typed evidence, expired handles, agent conversations, GitHub setup, remote pairing, and host enrollment.
Full workspace cases cover a locked publication, its reconciliation action, the saved diff, and CI results. Invocation cases cover active and unconfirmed Stop controls.
Coverage cases include modules without active bindings, mixed declaration support, and inactive declaration details at standard and accessibility text sizes.
These cases use validated in-memory reviews and bounded protocol fakes. Their visible dates, identifiers, and source are synthetic and fixed.
Run the module unit and snapshot bundles through the repository test command.
