# Compiled view layout audit

`./view-layout-audit` guards against oversized SwiftUI value compositions without
constructing a view or executing `body`. SwiftSyntax inventories production
sources; the Swift compiler resolves concrete view and opaque body types;
`MemoryLayout` supplies their size, stride, and alignment.

The default ceiling is strictly below 16 KiB for both the view and its body.
This is a composition guardrail, **not** a stack-overflow detector: it does not
measure temporaries, call depth, dynamic stack allocations, or out-of-line data.
Simulator layouts do not prove physical-device stack behavior.

## Coverage and authoring

```sh
./view-layout-audit check
./view-layout-audit generate
```

Discovery covers production `Sources` beneath Shared, Where, and Ledger,
excluding test support, snapshot-testing implementation, macro implementation,
and prototypes. It follows local protocol inheritance, conformance extensions,
and simple aliases, including representables and shapes. Protocols need explicit
exemptions; their concrete conformers are measured. Module platform assignments live in `platforms.json` and are checked against
discovery; adding or removing a UI module requires updating that mapping.
New generic views require
concrete `types` or a reasoned `exemption` in `registrations.json`.

Generic registrations are finite reference cases, not all possible type
arguments. The initial content-wrapper cases use `Text`; Flyover uses a named
screen ID and LifecycleContainer uses a Sendable value with Text surfaces.
Add representative production specializations when a wrapper's composition
requires more coverage. Compiler errors reject invalid registrations.

Same-file generated hooks can reach private file-scoped declarations. Qualified
nested declarations are discovered, but inaccessible private nested scopes may
require a hand-authored accessibility seam or explicit exemption. Ambiguous
same-name declarations fail discovery instead of silently dropping coverage.
Source generators, macro-produced views, complex aliases, and external protocol
inheritance that syntax cannot resolve are not exhaustively discovered.

Generated blocks are delimited and verified byte-for-byte. `generate` preserves
handwritten source and uses the repository's transactional replacement helper.
Do not hand-edit blocks or `ViewLayoutAudit.generated.swift`. All hooks and SPI
registries are behind `VIEW_LAYOUT_AUDIT`; ordinary builds exclude them.

## Builds and execution

Generate with `TUIST_VIEW_LAYOUT_AUDIT=1 ./ide --no-open`. This adds metatype-only
runner apps and independent companion apps for native source owners.
Companions copy source lists, resources, and audience settings, excluding the
original app entry-point file. They never launch production app lifecycles.
Package compilation is shared with the existing build. Each companion runs in
its own process to preserve package type identity.
The package runner links WhereUI and WhereIntents without listing WhereUI's
absorbed dependencies as extra products. Duplicate runtime-class diagnostics
invalidate a report.

Audit builds pass these settings without replacing audience conditions:

```sh
'OTHER_SWIFT_FLAGS=$(inherited) -DVIEW_LAYOUT_AUDIT'
"VIEW_LAYOUT_AUDIT_COMMIT=$(git rev-parse HEAD)"
"VIEW_LAYOUT_AUDIT_INPUT_HASH=$(./view-layout-audit fingerprint)"
```

`./test` adds them when `TUIST_VIEW_LAYOUT_AUDIT=1`. The existing Debug builder
includes the iOS harness; its worker executes the handed-off product. Beta and
Release workers run their own products; Ledger's macOS job runs its companion.
Local build schemes `ViewLayoutAudit-iOS` and `ViewLayoutAudit-macOS` exist only
in audit-enabled projects. Distribution generation never enables audit targets.

```sh
./view-layout-audit run --platform iOSSimulator --configuration Debug \
  --products ci-test-build/DerivedData/Build/Products/Debug-iphonesimulator \
  --discovery ci-test-build/ViewLayoutDiscovery \
  --shared --os 27.0 --output .build/view-layout-report
```

`run` never builds. It uses `./simulator`, installs only the audit app, enforces
a process timeout, and requires exactly one complete report. It preserves
per-runner logs and JSON plus the combined `report.json`, even when budget
validation fails. Each runner writes atomically to its own app container and
emits a completion marker; the collector rejects missing or partial results. It rejects products
with a different source fingerprint, commit, configuration, platform, or Xcode.
Reports record optimization and architecture and list inactive conditional
probes and explicit exemptions alongside measured cases.

## Baseline and failures

`baseline.json` contains only existing oversized exceptions, keyed by platform,
configuration, architecture, concrete case, and view/body. Each needs an exact
stride budget and reason. CI cannot raise budgets automatically.

```sh
./view-layout-audit baseline --report .build/view-layout-report/report.json \
  --reason 'Explain the existing composition and why it remains an exception'
./view-layout-audit validate --report .build/view-layout-report/report.json
```

Updates replace exceptions only for that report's matrix entry. New oversized
cases, growth, missing or duplicate records, unregistered exemptions, stale
exceptions, and resolved exceptions left in the baseline fail. A baseline update
must remain an explicit reviewed change. Reports are CI artifacts, not committed
machine output.

## Validation

Host policy/public-command tests live in `Tools/Tests/test_view_layout_audit.py`
and `test_view_layout_runner.py`; SwiftSyntax fixtures live in the discovery
module. `./view-layout-audit self-test` compiles trapping initializers/bodies, private
types, oversized/split bodies, and concrete generic cases against SwiftUI. It
also checks that an ordinary build emits no audit registry symbols.
The compiled harness is exercised on the real SDK in each CI build.
Retain focused Locations regression tests as a separate crash-regression guard.
