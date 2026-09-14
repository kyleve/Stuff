# PortholeGenerator

PortholeGenerator reads every Swift source file in an opted-in module. It emits a source archive, declaration catalog, and checked Swift calls.

The executable uses SwiftParser and SwiftSyntax. The root [package manifest](../../../Package.swift) pins their version.
The [build plugin](../PortholeBuildPlugin/README.md) invokes the executable before target compilation.

## Integration

Add PortholeRuntime and PortholeBuildPlugin to the adopting target.
Enable `-Xfrontend -disable-access-control` and `-enable-private-imports` for that target.
Call the generated entry point from the application composition root:

```swift
try await PortholeGeneratedModule.install(in: registry, scope: scope)
```

Each module has its own `PortholeGeneratedModule`. Use the module name to disambiguate imports.
The entry point registers capabilities and installs the exact compiled source archive.
After registration finishes, it installs the coverage document. The runtime resolves actual invocation support from installed handlers.
Declarations excluded by compiler conditions remain visible as inactive coverage entries. They never acquire invocation handlers.
Descriptive type and extension entries permit source inspection. Unsupported generic or isolation requirements retain their specific rejection reasons.
`sourceArchiveJSON` contains objects with `path`, `content`, and `sha256` fields. Paths are relative to the package root.
`coverageJSON` contains the complete versioned coverage document.
The optional `--catalog FILE` argument writes the same document as a standalone report.
The application exporter and compiler fixtures can request this report. The build plugin omits it to prevent redundant resource copies.
Every source declaration retains its stable identity, signature, compiler conditions, source location, hash, and final planner support or rejection reason.
Coverage records module identity and supplied build metadata without duplicating source content.
Repeated declaration signatures retain separate identities. The first occurrence keeps its semantic ID; later occurrences add a per-signature ordinal.
These IDs survive unrelated declaration and line edits. Adding an earlier identical occurrence changes that signature's later ordinals.
`PORTHOLE_BUILD_CONFIGURATION` and `PORTHOLE_TOOLCHAIN_ID` supply authoritative build labels.
The generator reads `xcrun swiftc --version` once when no toolchain label is supplied. Source-only inventories inherit the same labels.
Missing configuration labels remain `unknown`. The generated `isCompiledWithDebugCondition` value separately records the target compiler's `DEBUG` condition.
The application must supply its stamped build identity when it composes package catalogs. Swift's language version does not identify the toolchain.

## Source-only coverage

The application exporter can pass `--inventory-manifest FILE` for debugger implementation modules that cannot safely receive automatic bindings.
The JSON object contains `modules`. Each module has `name`, `reason`, `sources`, and `excludedFiles` fields.
Source paths are absolute generator inputs within the declared root. Each excluded file has a `path` and a `reason`.

The generator bundles allowed source text and hashes alongside application sources.
It publishes every inventoried declaration with an unsupported reason under its original module identity.
Excluded credential files receive a path-and-reason descriptor without source content.
The coverage document records source-only and excluded-file origins explicitly. These modules receive no imports, executable bindings, or live object roots.

## Dispatch contract

The planner emits functions, initializers, enum case constructors, property getters, and actor-owned property setters with concrete supported types.
Private and fileprivate access uses the adopting target's compiler flag. Generated calls still obey Swift's isolation and type rules.
Actor calls preserve executor ownership. Immutable Sendable storage supports synchronous reads within the same module.
MainActor members use MainActor helper functions. Constructors retain their result as a scoped object reference.
Synchronous calls preserve synchronous overload selection, including inherited protocol requirements. Actor helpers select synchronous overloads on the actor.
Constructor and opaque result handles use the runtime's bounded result pool.
Enum constructors preserve payload labels and return typed handles, including cases with no payload and raw-value cases.
Payload labels become argument keys. Unnamed payloads receive positional keys that do not collide with those labels.
Payload defaults remain descriptive; each generated call requires all payload arguments.
Ignored function and initializer arguments also receive distinct positional keys. Native calls preserve their original argument labels.
Repeated external function labels use distinct local names when available, then positional keys. Unique external labels keep their existing keys.
Void arguments accept JSON null and reject other values.
Case construction never calls the enum's encoder or its raw-value initializer.
Non-Sendable enum construction uses MainActor value boxes. This execution boundary does not change the enum's declared isolation or Sendable conformance.
Synchronous instance APIs use those same boxes. Nonisolated asynchronous APIs still require a Sendable receiver.
Each concrete enum also receives a generated `$inspect` receiver operation. It reads the active case without constructing a value or invoking an accessor.
The result contains `case` and `payloads`. Each payload records its unique `name`, native `label`, qualified `type`, and `value`.
Booleans, strings, built-in integers, and finite Float/Double values use direct JSON values.
Other payloads use typed scoped handles, including MainActor boxes for non-Sendable values.
Inspection never uses Mirror, raw-value getters, or application Encodable code. It remains a classified read. Enum construction still requires approval.
Conditional case patterns preserve their source compiler conditions. Empty enums have no inspection handler.
An unsafe payload, unavailable case, or unbound owner prevents inspection and produces a precise coverage reason.
This conservative check includes inactive cases. It never reports a partial payload set as a complete inspection.
Coverage distinguishes the generated `enumerationInspection` operation from the original `enumerationCase` constructors.
Unsupported payloads retain their source declarations and specific type or isolation errors.
Descriptors carry typed execution ownership. Explicit `nonisolated` members do not inherit the enclosing type's declared isolation.
A synchronous enum adapter can still run on MainActor to use its value box.
Nested nominal types keep their declared isolation. Synchronous APIs on nested values can use MainActor boxes when an enclosing type has MainActor ownership.
The planner recognizes MainActor through first-party nominal inheritance and SDK SwiftUI View conformance.
First-party extensions of View do not redefine that protocol.

Arguments and results require a known Sendable representation or a typed MainActor value box.
The planner recognizes primitives, selected Foundation values, containers, actors, and explicit Sendable conformances.
MainActor protocol values use scoped, actor-owned boxes. Concrete protocol instance signatures can call through those boxes without making the existential Sendable.
Non-Codable arrays and boxed containers use typed object references. Character and Substring use explicit string conversions.
Local dependency sources supply type facts. External package products need a supported primitive signature or a separate concrete adapter.

Generic specializations, executable closures, inout arguments, subscripts, failable initializers, unknown inferred types, and value mutation remain explicit unsupported entries.
Nested types and members also require concrete ancestors. The planner preserves this restriction when an extension introduces a nested type in another file.
Availability-constrained declarations also require an adapter. The catalog includes source declarations in inactive branches, while installed capabilities follow the target's conditional compilation.
Synthesized macro members and implicit memberwise initializers are absent from the source inventory.

Ordinary stored instance getters use a read effect. Lazy, static, and macro-transformed getters use an unknown effect.
Stored getters also require approval when their result serialization can execute application Encodable code.
The generator directly retains values without a known encoder. It does not dynamically invoke an unexpected application encoder for a read.
Methods and computed getters also use an unknown effect. Setters use a mutation effect.
Enum constructors use an unknown effect because decoding payload arguments can execute application code.
The runtime applies its approval policy to these effects.
Generated helpers check cancellation after argument resolution and immediately before the native call. Cancellation cannot stop synchronous Swift code that already runs.

## Normal-source guard

`-disable-access-control` weakens access checking throughout the target, including original source files. It is an unsupported compiler option.
Every instrumented build must have a matching normal-source check with both private-access flags removed and `PORTHOLE_ORIGINAL_SOURCE_CHECK` defined.
The generated file retains its public installation entry point but excludes private call sites in this check.
Use the same SDK, optimization, compilation mode, and compilation conditions for both builds.
The [compiler contract tool](../../../Tools/porthole_compiler_contract.py) builds both paths with fresh products.
CI covers Debug, Beta, and Release with both the simulator SDK and the iPhoneOS SDK.
Each pair uses the pinned Xcode, arm64, and two concurrent build tasks.
The tool checks actual compiler commands for every adopting module and the application.
Each target retains its configured optimization and compilation mode.
The two paths must match except for private-access flags and the guard condition.
The result and build logs remain available when a build fails. These builds do not establish physical-device execution or App Review acceptance.

Run one pair with a new output directory:

```bash
python3 Tools/porthole_compiler_contract.py --configuration Beta --sdk iphoneos --jobs 2 --output .build/porthole-validation/beta-device-pair
```

Private-import emission preserves private symbol linkage across source files without forcing whole-module compilation.
The host compiler test checks per-source outputs, private mutation, overload selection, and linkage in Debug and optimized builds.
It checks Swift 5 and Swift 6 language modes with complete concurrency checking and warnings treated as errors.
Each language and optimization pair runs with DEBUG enabled and disabled. The executable checks both active and inactive coverage rows.
The same fixture inspects private enums, exact integer payloads, typed collections, and actor-owned protocol payloads without application serialization.
It rejects unsafe inspection signatures, expired scopes, and non-finite scalar payloads. Constructor approval remains required.
Runtime libraries use Swift 6. Each original-source check and instrumented fixture uses the same language mode and optimization level.
Registration uses synchronous batches of at most 16 declarations on the registry actor. An isolated registry parameter permits each batch to register without suspension.
The asynchronous installer checks cancellation between batches and uses one actor hop per batch. This avoids repeated coroutine cleanup paths for metadata values.
The compiler fixture executes callable, descriptive, and excluded-source registrations in both language modes. A large-catalog regression checks the synchronous batch boundary and declaration count.
Do not force whole-module mode through package unsafe flags. Xcode must control the compilation mode and its expected output files together.

The scanner rejects unconditional private declaration collisions across files. Conditional collisions and ambiguous compiler lookup still fail target compilation.
Resolve collisions explicitly before adopting the module. Never remove a declaration from the catalog to conceal an instrumentation failure.

## Validation

The [tests](Tests) cover source inventory, isolation analysis, conditional imports, source escaping, and generated private calls.
The repository test command owns host-tool validation. Test generated fixtures with both the private-access flag and the normal-source guard.
