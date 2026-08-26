import CoreGraphics
import ThrowCore

/// Deterministic label admission that preserves every mark and stabilizes labels across frames.
struct ProjectionLabelCollisionResolver {
    private static let rangeHysteresis = try! NauticalMiles(value: 0.25)

    private var previouslyVisible: Set<LayerMarkID> = []

    mutating func resolve(_ frame: ProjectionFrame) -> ProjectionFrame {
        let candidates = frame.marks
            .filter { $0.label != nil }
            .sorted(by: precedes)
        var acceptedRects: [CGRect] = []
        var visible: Set<LayerMarkID> = []

        for mark in candidates {
            let rect = labelRect(for: mark)
            guard acceptedRects
                .contains(where: { $0.intersects(rect.insetBy(dx: -0.006, dy: -0.004)) }) == false
            else {
                continue
            }
            acceptedRects.append(rect)
            visible.insert(mark.id)
        }
        previouslyVisible = visible

        return ProjectionFrame(
            mode: frame.mode,
            generatedAt: frame.generatedAt,
            geography: frame.geography,
            geographyOpacity: frame.geographyOpacity,
            marks: frame.marks.map { mark in
                ProjectedMark(
                    id: mark.id,
                    point: mark.point,
                    range: mark.range,
                    glyph: mark.glyph,
                    label: visible.contains(mark.id) ? mark.label : nil,
                    secondaryProminence: mark.secondaryProminence,
                    orientationDegrees: mark.orientationDegrees,
                    opacity: mark.opacity,
                    labelOpacity: mark.labelOpacity,
                    altitudeIsApproximate: mark.altitudeIsApproximate,
                )
            },
        )
    }

    private func precedes(_ lhs: ProjectedMark, _ rhs: ProjectedMark) -> Bool {
        let leftIsAirport = if case .airport = lhs.glyph { true } else { false }
        let rightIsAirport = if case .airport = rhs.glyph { true } else { false }
        if leftIsAirport != rightIsAirport { return rightIsAirport }
        switch (lhs.range, rhs.range) {
            case let (left?, right?):
                let difference = abs(left.value - right.value)
                if difference <= Self.rangeHysteresis.value {
                    return visibleOrStableOrder(lhs, rhs)
                }
                return left < right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                break
        }

        let leftDistance = radialDistance(lhs)
        let rightDistance = radialDistance(rhs)
        let difference = abs(leftDistance - rightDistance)
        if difference < 0.025 {
            let leftWasVisible = previouslyVisible.contains(lhs.id)
            let rightWasVisible = previouslyVisible.contains(rhs.id)
            if leftWasVisible != rightWasVisible { return leftWasVisible }
        }
        if leftDistance != rightDistance { return leftDistance < rightDistance }
        return stableKey(lhs.id) < stableKey(rhs.id)
    }

    private func visibleOrStableOrder(_ lhs: ProjectedMark, _ rhs: ProjectedMark) -> Bool {
        let leftWasVisible = previouslyVisible.contains(lhs.id)
        let rightWasVisible = previouslyVisible.contains(rhs.id)
        if leftWasVisible != rightWasVisible { return leftWasVisible }
        return stableKey(lhs.id) < stableKey(rhs.id)
    }

    private func radialDistance(_ mark: ProjectedMark) -> Double {
        hypot(mark.point.x - 0.5, mark.point.y - 0.5)
    }

    private func stableKey(_ id: LayerMarkID) -> String {
        "\(id.layerID.rawValue)/\(id.namespace.rawValue)/\(id.rawValue)"
    }

    private func labelRect(for mark: ProjectedMark) -> CGRect {
        let characterCount = Double(max(
            mark.label?.primary.count ?? 0,
            mark.label?.secondary?.count ?? 0,
        ))
        let isDetailOnly = mark.label?.primaryRole == .detail
        let characterWidth = isDetailOnly ? 0.006 : 0.008
        let horizontalPadding = isDetailOnly ? 0.016 : 0.02
        let minimumWidth = isDetailOnly ? 0.045 : 0.055
        let width = min(0.24, max(
            minimumWidth,
            characterWidth * characterCount + horizontalPadding,
        ))
        let hasSecondaryLine = mark.label?.secondary != nil
        let singleLineHeight = isDetailOnly ? 0.022 : 0.028
        return CGRect(
            x: mark.point.x + 0.016,
            y: mark.point.y - (hasSecondaryLine ? 0.021 : singleLineHeight / 2),
            width: width,
            height: hasSecondaryLine ? 0.042 : singleLineHeight,
        )
    }
}
