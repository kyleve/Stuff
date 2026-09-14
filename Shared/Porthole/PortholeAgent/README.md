# PortholeAgent

PortholeAgent runs the native Swift AI SDK inside the app. It supports OpenAI
and Anthropic with an explicit, user-selected model. The dependency pin lives
in the root Package.swift.

Create one `PortholeAgentJournal` and one `PortholeAgentKeychain` at the debugger
composition root. Build `PortholeAgentFactory` with the common tool dispatcher.
The factory creates a session for each provider configuration.

```swift
let journal = try PortholeAgentJournal(url: transcriptURL)
let keys = PortholeAgentKeychain(service: "com.example.porthole.providers")
let factory = PortholeAgentFactory(
    credentials: keys,
    tools: toolDescriptors,
    journal: journal,
    redaction: PortholeAgentRedaction(secrets: otherKnownSecrets),
    executor: dispatch
)
```

The setup UI stores keys with `store(apiKey:for:)`. The user grants provider
consent through `journal.setConsent(for:granted:)`. Consent applies only to that
provider. Each model request checks consent again. Revocation also cancels the
active UI session.

Create a session with `factory.create(configuration:)`. Read complete history
with `journal.resumeMessages()`, append a user message, and consume
`session.stream(messages:)`. The stream includes text, tool calls, evidence,
complete model messages, and final usage. Cancellation reaches the SDK and native
tool tasks. The consumer must drain the bounded stream.

## Tool execution and recovery

Tools receive `PortholeAgentInvocation`. Its `operationID` is a durable UUID.
Use that UUID for the common runtime invocation. The journal records intent
before the native executor runs. The same provider call retains the same
operation identity while the dispatcher waits for approval.

The dispatcher owns authorization and approval. It can suspend for trusted UI
approval, then retry the same native invocation. An executor failure stops the
agent loop. The model cannot automatically retry an uncertain mutation.

The journal stores complete user, assistant, tool-call, and tool-result messages.
It reconstructs completed operations if the app stops before a step is saved.
It never executes restored calls. Proposed, executing, or uncertain operations
block resume. Inspect the common runtime journal, then call `reconcile` with a
confirmed result. Cancellation does not roll back native effects.

The user can acknowledge an unknown outcome when no receipt exists. This saves
terminal uncertainty evidence and allows another message. The old operation
cannot execute again. Its evidence still says that the outcome is unknown.

## Investigations

`PortholeAgentInvestigationLibrary` owns separate transcript files and the selected
investigation. Its anchor URL determines the adjacent `.investigations` directory.
Create one library at the composition root. Reuse its cached journal actors.

Each investigation saves its original context and scope generation. Selecting
another screen does not change that evidence. A new investigation gets a new
file. Late results therefore stay in their original investigation.

Each run records the chosen provider and model. The UI restores that choice
when the user resumes a conversation. A live scope can serve its original
selection after the UI closes and reopens. Expired scopes cannot serve live calls.

The user can explicitly continue with the current app context. This appends a
capture with source and build provenance, then changes the scope for future tools.
It preserves original evidence and never translates old object handles. Uncertain
operations still need reconciliation or acknowledgment before this action.

## Data boundaries

Provider keys stay in the device's unlocked Keychain. They are excluded from
configuration, transcripts, JavaScript, and tool schemas. Supply other known
secrets through `PortholeAgentRedaction`. It filters exact secrets and common
structured credential fields. It also recognizes common API key prefixes and
handles secrets split across text chunks.
This filter does not classify every possible secret in arbitrary source text.

The SDK stores JSON numbers as Double. Unsafe integer arguments fail before
native execution. Large Int64 and UInt64 results become exact decimal strings for the
model. Use the console's BigInt syntax for exact large integer arguments.

Provider retries are disabled. Each run has step, token, elapsed-time, stream
buffer, and accumulated-output limits. Native tools must cooperate with
cancellation. Provider APIs need network access; no desktop process is required.

Run `./test PortholeAgentTests`. Tests use a scripted implementation of the SDK's
LanguageModel protocol. They make no provider requests.
