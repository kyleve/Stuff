//
//  SnapshotKit.swift
//  SnapshotKit
//

/// SnapshotKit is the generic, shippable half of the snapshot-testing framework.
///
/// It owns the appearance *matrix*: a ``SnapshotConfiguration`` describing one
/// rendering variant (color scheme, Dynamic Type, contrast, device frame, and
/// whether it is a standard or accessibility capture), the presets and
/// `combinations(...)` that expand into a matrix, the ``SnapshotProviding``
/// protocol a component adopts to declare its variants, and the SwiftUI preview
/// *cutsheet* that renders them in Xcode.
///
/// It imports only SwiftUI / Foundation / UIKit — never the test-only snapshot
/// comparison engine — so a UI module can drive its `#Preview`s from the exact
/// configurations its snapshot tests assert against. The comparison + capture
/// pipeline lives in the sibling `SnapshotKitTesting` module. See `README.md`.
public enum SnapshotKit {}
