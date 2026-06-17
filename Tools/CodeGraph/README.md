# CodeGraph

A UML-style visualizer for how the types in this repo fit together —
inheritance, conformance, ownership, construction, and other data flows —
rendered as an interactive, filterable graph you can rearrange and save.

It is two pieces that talk through a single JSON file:

| Piece | What it is | Where |
|-------|------------|-------|
| `code-graph-extract` | A macOS command-line tool that reads the compiler **index store** and emits `graph.json`. | [`Sources/code-graph-extract`](Sources/code-graph-extract) |
| `CodeGraphViewer` | A standalone **Mac Catalyst** SwiftUI app that loads `graph.json` and draws it. | [`Viewer`](Viewer) |
| `CodeGraphModel` | The dependency-free data model both sides share (`Node`, `Edge`, `CodeGraph`). | [`CodeGraphModel`](CodeGraphModel) |

The model lives in its own package with **no dependencies** so the sandboxed
Catalyst app can consume it without pulling in `indexstore-db` (which is
macOS/host-only). The extractor and the viewer never link against each other —
they only agree on the shape of `graph.json`.

## Quick start

```bash
Tools/CodeGraph/run.sh
```

That builds the extractor, runs `tuist generate` + `xcodebuild
build-for-testing` to produce a fresh index, harvests the graph into
`Tools/CodeGraph/.codegraph/graph.json`, then builds and opens the viewer.
Pick the printed `graph.json` from the open panel **once** — the app keeps a
security-scoped bookmark and reopens it automatically next launch.

Re-running anything that rewrites `graph.json` (the script, or watch mode
below) hot-reloads the open viewer.

> Requires macOS with Xcode 26+ and the toolchain pinned in [`.mise.toml`](../../.mise.toml)
> (Tuist). The viewer is iOS 26 / Mac Catalyst, matching the rest of the repo.

## The extractor

`code-graph-extract` resolves an index store, opens it with `IndexStoreDB`,
walks every symbol and relation, and writes `graph.json` atomically.

By default it does a **dedicated, reproducible build** into a fixed
derived-data directory (`.codegraph/DerivedData`) so it never disturbs your
Xcode build, then reads the index store Xcode wrote there.

```bash
swift build -c release --product code-graph-extract
.build/release/code-graph-extract --repo /path/to/repo
```

Useful flags (`--help` for the full list):

| Flag | Purpose |
|------|---------|
| `--repo <path>` | Repository root (default: current directory). |
| `--output <path>` | Where to write `graph.json` (default: `<repo>/Tools/CodeGraph/.codegraph/graph.json`). |
| `--scheme <name>` | Scheme for the dedicated build (default: `Stuff-Workspace`). |
| `--destination <dst>` | `xcodebuild` destination (default: an iPhone 17 simulator). |
| `--index-store-path <path>` | Read an existing index store instead of building. |
| `--skip-build` | Reuse the index store from a prior dedicated build; never invoke `xcodebuild`. |
| `--watch` | Stay running and re-extract whenever the index store changes. |
| `--watch-debounce <seconds>` | Settle time before re-extracting in watch mode (default: `1.0`). |

### Watch mode

```bash
.build/release/code-graph-extract --repo "$PWD" --watch
```

This blocks and rewrites `graph.json` each time the index store's `units`
directory changes — i.e. every time you build in Xcode. Leave the viewer open
and it follows along live. (`run.sh` is one-shot and will point you here if you
pass `--watch`.)

## The viewer

`CodeGraphViewer` renders edges in a SwiftUI `Canvas` and nodes as interactive
chips laid out by a force-directed engine (Fruchterman–Reingold with
grid-accelerated repulsion, module-centroid gravity, a deterministic seed, and
pinned nodes). Highlights:

- **Pan / zoom**, click to select, and an **inspector** listing a node's
  declaration plus incoming/outgoing relationships (each row jumps to the other
  end).
- **Drag to pin** a node where you want it; the rest re-settles around it.
- **Expand/collapse** a type to reveal its members.
- **Focus** on a node to show only its N-hop neighborhood.
- **Filters**: by module, node kind, edge kind, origin (first-party / test /
  external), and a name search.
- **Saved views**: name the current arrangement (pins + filters + focus) and
  return to it. State is stored per repo path in the app container and
  reconciled against re-extracted graphs (references to vanished symbols are
  dropped).

### Open it in Xcode

```bash
cd Tools/CodeGraph/Viewer && mise exec -- tuist generate --no-open
open CodeGraphViewer.xcworkspace
```

## Data model

`graph.json` decodes to a [`CodeGraph`](CodeGraphModel/Sources/CodeGraphModel/CodeGraph.swift):
a list of `modules`, `nodes`, and `edges`, plus the `repoPath`, git `commit`,
and `generatedAt` timestamp.

A **node** has a stable `id` (the compiler USR for symbols, `module:<name>` for
modules), a `name`, a `module`, an `origin`, an optional `parentID` /
`file` / `line`, and a `kind`:

`class` · `struct` · `enum` · `protocol` · `actor` · `extension` · `typealias` ·
`associatedType` · `method` · `property` · `initializer` · `subscript` ·
`enumCase` · `function` · `module` · `other`

An **edge** is directed (`source` → `target`), records how many occurrences
collapsed into it (`count`), an optional `viaMemberID` (the member the relation
flowed through), and a `kind`:

`inheritance` · `conformance` · `override` · `member` · `propertyType` ·
`paramOrReturnType` · `construction` · `genericConstraint` · `associatedType` ·
`moduleDependency` · `reference`

Structural kinds (`inheritance`, `conformance`, `override`, `member`,
`moduleDependency`) form the UML backbone; the rest are usage / data-flow
references.

## Layout

Everything `.codegraph/` (the dedicated build's derived data and `graph.json`)
and the generated Xcode project are git-ignored — see [`.gitignore`](.gitignore).
