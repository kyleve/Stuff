import BroadwayCore
import BroadwayUI
import SwiftUI
import TestHostSupport
import Testing
import UIKit
@testable import WhereUI

@MainActor
struct WhereScaledDimensionTests {
    @Test(arguments: DynamicTypeSize.allCases)
    func matchesSwiftUIScaledMetric(size: DynamicTypeSize) throws {
        let box = ScaledDimensionProbeBox()
        let host = UIHostingController(rootView: ScaledDimensionProbe(box: box)
            .dynamicTypeSize(size))
        try show(host) { _ in
            try waitFor { box.value != nil }
            let measured = try #require(box.value)
            let resolved = WhereScaledDimension.value(
                52,
                relativeTo: .title2,
                category: .init(size),
            )
            #expect(abs(measured - resolved) < 0.01)
        }
    }
}

private final class ScaledDimensionProbeBox {
    var value: CGFloat?
}

private struct ScaledDimensionProbe: View {
    let box: ScaledDimensionProbeBox
    @ScaledMetric(relativeTo: .title2) private var diameter: CGFloat = 52

    var body: some View {
        Color.clear.onChange(of: diameter, initial: true) { _, value in
            box.value = value
        }
    }
}
