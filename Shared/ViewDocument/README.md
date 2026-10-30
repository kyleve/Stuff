# ViewDocument

ViewDocument converts a versioned document into read-only SwiftUI content. It supports text, images, shapes, finite groups, ordered modifiers, and transform animations.

`ViewDocumentCore` owns Codable values and validation. `ViewDocumentUI` renders them. Neither module requires Broadway or Where.

## Render a document

1. Prepare images and approved symbols with `ViewDocumentAssets`.
2. Decode with `ValidatedViewDocument.decode(_:resources:limits:)`.
3. Construct `ViewDocumentView` with that document, its assets, appearance values, and rendering policy.

Decode and validate outside `body`. The renderer initializer throws if its assets differ from the validated resource requirements.
For trait-driven rendering, construct `PreparedViewDocument` once. Pass it to the nonthrowing renderer initializer as appearance inputs change.

The schema version is 1. Codable enums use Swift's synthesized associated-value representation. Node identities and asset keys encode as strings through their RawRepresentable Codable conformance.

```json
{
  "schemaVersion": 1,
  "root": {
    "id": "greeting",
    "content": { "text": { "_0": "Hello" } },
    "modifiers": [],
    "accessibility": { "automatic": {} }
  }
}
```

`ViewDocument.Content` and `ViewModifierDescriptor` define the complete vocabulary. Arrays of modifiers apply in source order. Documents contain no executable expressions, actions, bindings, or loops.

General content preserves text accessibility and supports image labels and grouping. Decoration policy hides the tree from accessibility. All document content is noninteractive.

Hosts supply semantic background colors and dimension scales. Fonts preserve semantic Dynamic Type behavior. An omitted font weight preserves the system weight of that text style. Use fixed sizes only for intentional fixed artwork.

Assets are prepared SwiftUI images keyed by typed identities. Hosts load packaged PNG/JPEG assets and register approved symbols before rendering. Documents cannot access paths or URLs.

Animations sample elapsed seconds. Curves use linear, quadratic ease-in/out, or cosine ease-in-out interpolation. Autoreversing repetition counts complete forward-and-back cycles. Each animation has a separate static pose. Inactive views render that pose and restart on activation. Finite animations stop requesting frames after their final cycle.

Validation checks versions, ranges, resource availability, identity uniqueness, and complexity. Standard limits are 1 MiB, depth 16, 256 nodes, and 32 animated nodes. Validation errors carry a document path. Unknown enum operations fail decoding; additive object fields follow Codable's forward-compatible decoding behavior.

Validation also bounds cumulative scale amplification across modifiers, ancestor nodes, and animation poses. Individually valid scales can otherwise combine into transforms that native rendering cannot display.
