# Throw protocol specifications

These bounded models check narrow concurrency claims in Throw. Each concern contains an editable
PlusCal model, TLC configurations, a manifest, and a source correspondence document.

Run one concern from the repository root:

```sh
./tla-check PreferenceTransactions
```

[`PollingPublication`](PollingPublication/README.md) checks token-bound, ordered polling updates
across replacement, recovery, frame construction, and deactivation.

Use [`Where/Specifications/README.md`](../../Where/Specifications/README.md) for the shared
authoring and checker rules.
