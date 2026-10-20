// Explicit returns suppress ViewBuilder inference in these trapping getters.
// swiftformat:disable redundantReturn
import Foundation
import SwiftUI

private func neverEvaluate<T>() -> T {
    fatalError("Must not evaluate a view body")
}

private struct WideValue: View {
    typealias Block = (SIMD64<Double>, SIMD64<Double>)
    let storage: (
        Block,
        Block,
        Block,
        Block,
        Block,
        Block,
        Block,
        Block,
        Block,
        Block,
        Block,
        Block,
        Block,
        Block,
        Block,
        Block
    )
    var body: Never {
        return neverEvaluate()
    }
}

private struct Oversized: View {
    init() {
        fatalError("Must not initialize a view")
    }

    var body: WideValue {
        return neverEvaluate()
    }
}

private struct Child: View {
    init() {
        fatalError("Must not initialize a view")
    }

    var body: Text {
        return neverEvaluate()
    }
}

private struct Split: View {
    init() {
        fatalError("Must not initialize a view")
    }

    var body: HStack<TupleView<(Child, Child)>> {
        return neverEvaluate()
    }
}

private struct Generic<Content: View>: View {
    let content: Content
    var body: Content {
        return neverEvaluate()
    }
}

@main
@MainActor
private enum CompiledProbe {
    static func main() {
        // Uses the exact generated measurement implementation, in this source
        // module, to prove private access and the absence of value evaluation.
        print(_ViewLayoutAuditRegistry.measure(Oversized.self, id: "oversized"))
        print(_ViewLayoutAuditRegistry.measure(Split.self, id: "split"))
        print(_ViewLayoutAuditRegistry.measure(Generic<WideValue>.self, id: "generic-wide"))
        print(_ViewLayoutAuditRegistry.measure(Generic<Child>.self, id: "generic-small"))
    }
}
