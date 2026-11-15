# Browser prototypes with Astro

Use the repository's pinned Astro dependency for interactive browser experiments unless the user selects another format or the experiment requires one.
This procedure supports an authorized prototype; it does not authorize implementation during planning-only work or choose the eventual native app architecture.

## Set up the experiment

- Keep the project beside its numbered plan, usually `Plans/YYYY-MM-DD-topic/Prototype/`. Give its README the exact working directory, start/check/build commands, sample-data limits, and reset behavior.
- Reuse the root `package.json`, `package-lock.json`, and installed `node_modules`. If dependencies are missing, run `mise exec -- npm ci` from the repository root. Do not scaffold a second dependency tree or fetch a newer Astro release.
- Put the active page in `src/pages/index.astro` and its client code/styles in Astro's watched import graph. Do not serve the whole editable app as an unprocessed file under `public/`; that bypasses the intended development loop.
- Keep Astro/Vite caches and build output ignored and local to the prototype. Restrict dev-server file access to the prototype's sources and required dependencies, rather than exposing the repository root. Historical artifacts stay clearly labeled; identify one current source.

## Run and share the preview

Use the repository command from the repository root (see [`./prototype --help`](../../../../prototype) and [tooling details](../../../../Tools/README.md#browser-prototypes)):

```sh
./prototype start Plans/YYYY-MM-DD-topic/Prototype --lan
./prototype status Plans/YYYY-MM-DD-topic/Prototype
./prototype logs Plans/YYYY-MM-DD-topic/Prototype
./prototype stop Plans/YYYY-MM-DD-topic/Prototype
```

The command owns pinned tooling, absolute project paths, background lifecycle, ownership checks, port conflicts, HTTP readiness, and current reachable IPv4 URLs. Run `status` again at handoff; network addresses can change while the server stays running. Give the user the verified local and network URLs. A phone uses the latter on the same network. Keep this a development preview; do not add public hosting or a tunnel unless requested.

Leave the review server running for an interactive handoff and provide its stop command; stop temporary verification servers. Record its worktree/project and owner in the execution checkpoint, including the coordinator's reporting duty under [Delegated execution handoff](../SKILL.md#delegated-execution-handoff).

## Verify the development loop

```sh
./prototype check Plans/YYYY-MM-DD-topic/Prototype
./prototype build Plans/YYYY-MM-DD-topic/Prototype
```

Exercise the served prototype in a browser at the intended viewport sizes. Make and revert a small visible source edit and observe automatic updates without manually reloading. Cover the edited source kinds, such as route markup, client code, and CSS; a successful HTTP response or build alone does not establish live reload. Record whether an update preserves the sample session or performs a full reload that resets it.

Check both loopback and the actual LAN address, including live reload when reachable. A request from the host to its own LAN address is not physical-phone verification; distinguish that evidence from an actual device test. Confirm the served final content and source revision after reverting the probe, then record checks, URLs, remaining limits, and publication state in the plan before the completion notice.
