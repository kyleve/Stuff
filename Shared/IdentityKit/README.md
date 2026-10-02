# IdentityKit

IdentityKit provides UUID identities that the compiler keeps separate by domain.
It uses Foundation and has no repository dependencies.

## Use

Add the `IdentityKit` product from the root package to the consuming target.
Declare an alias on the domain type:

```swift
import IdentityKit

struct Sample {
    typealias ID = TypedID<Sample>
    let id: ID
}

let sampleID = Sample.ID()
```

A `TypedID<Sample>` cannot stand in for a `TypedID<Revision>`.
The owner has no protocol requirements. It is never stored or transferred.

`TypedID` supports `Hashable`, `Comparable`, `Sendable`, and `Codable`.
Use `init(rawValue:)` when reading a UUID from persistence or a system API.
Unwrap `rawValue` only at that boundary.

## Compatibility

Encoding writes the same single UUID string as Foundation's `UUID`.
Decoding rejects invalid UUIDs. Renaming the owner leaves stored data unchanged.
Ordering uses the UUID string as a deterministic tie-breaker. It does not imply chronology.

## Tests

Run `./test IdentityKitTests` for wire compatibility, invalid input, ordering,
set membership, and transfer across actors.
