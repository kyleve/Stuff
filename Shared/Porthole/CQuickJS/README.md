# CQuickJS

This target contains the QuickJS-NG interpreter and Porthole's C bridge.
The exact upstream revision and file hashes are in [VENDOR.json](VENDOR.json).
The upstream MIT notice is in [LICENSE](LICENSE).

Only the interpreter core is included. The shell, command-line tools, and
`quickjs-libc` host APIs are excluded. The build uses no JIT.

The public header exposes an opaque runtime, bounded job pumping, and native
promise completion. PortholeJavaScript owns the runtime and its serial queue.
Keep runtime creation, calls, and destruction on that queue.

The Swift tests in PortholeJavaScript cover this bridge. Run
`./test PortholeJavaScriptTests` from the repository root.

When updating upstream, copy only the recorded core files. Preserve them without
edits, update their hashes, and include the new license. Keep wrapper changes
outside `Sources/vendor`.
