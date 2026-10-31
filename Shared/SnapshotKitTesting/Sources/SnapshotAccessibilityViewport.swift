import ObjectiveC
import UIKit

/// Preserves native bar elements outside the simulator's physical screen while
/// capturing a larger synthetic viewport. Layout and annotation coordinates stay unscaled.
@MainActor
enum SnapshotAccessibilityViewport {
    static func withUnclippedNavigationBars<Result>(
        in root: UIView,
        operation: () throws -> Result,
    ) rethrows -> Result {
        guard let window = root.window, let scene = window.windowScene else {
            return try operation()
        }
        let available = scene.effectiveGeometry.coordinateSpace.bounds
        let extent = window.convert(window.bounds, to: scene.effectiveGeometry.coordinateSpace)
        let scale = min(1, available.width / extent.width, available.height / extent.height)
        guard scale < 1 else { return try operation() }

        let bars = navigationBars(in: root)
        let originalTransform = window.transform
        let originalCenter = window.center
        window.transform = originalTransform.concatenating(CGAffineTransform(
            scaleX: scale,
            y: scale,
        ))
        window.center = CGPoint(x: available.midX, y: available.midY)
        var elements: [ObjectIdentifier: NSArray] = [:]
        for bar in bars {
            if let nativeElements = bar.accessibilityElements {
                elements[ObjectIdentifier(bar)] = nativeElements as NSArray
            }
        }
        window.transform = originalTransform
        window.center = originalCenter

        // Do not assign accessibilityElements: that would replace UIKit's automatic
        // behavior with a stored list after capture. Intercept only these instances
        // for this synchronous parse, then restore the original getter implementations.
        let selector = #selector(UIView.accessibilityElements)
        var overrides: [GetterOverride] = []
        var methods: Set<Method> = []
        for bar in bars {
            guard let method = class_getInstanceMethod(type(of: bar), selector),
                  methods.insert(method).inserted
            else { continue }
            let original = method_getImplementation(method)
            let getter = unsafeBitCast(original, to: Getter.self)
            let capturedElements = elements
            let block: @convention(block) (AnyObject) -> NSArray? = { object in
                if let captured = capturedElements[ObjectIdentifier(object)] { return captured }
                return getter(object, selector)
            }
            let replacement = imp_implementationWithBlock(block)
            method_setImplementation(method, replacement)
            overrides.append(GetterOverride(
                method: method,
                original: original,
                replacement: replacement,
            ))
        }
        defer {
            for override in overrides.reversed() {
                method_setImplementation(override.method, override.original)
                imp_removeBlock(override.replacement)
            }
        }
        return try operation()
    }

    private typealias Getter = @convention(c) (AnyObject, Selector) -> NSArray?

    private struct GetterOverride {
        let method: Method
        let original: IMP
        let replacement: IMP
    }

    private static func navigationBars(in view: UIView) -> [UINavigationBar] {
        (view as? UINavigationBar).map { [$0] } ?? view.subviews.flatMap { navigationBars(in: $0) }
    }
}
