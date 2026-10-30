import Observation
import SwiftUI

/// Holds the visible calendar still until its destination has finished scrolling.
/// Matching uses viewport rectangles, so moving tiles cannot alter scroll-target layout.
@MainActor
@Observable
final class CalendarZoomTransitionModel {
    typealias Mode = CalendarPresentationModel.Mode
    typealias Target = CalendarPresentationModel.Target

    /// Points: ignore subpixel rounding in viewport sizes and scroll-edge alignment.
    private nonisolated static let geometryTolerance: CGFloat = 1

    struct ID: Hashable { let rawValue: Int }

    struct Measurement: Equatable {
        let mode: Mode
        let frames: [Target: CGRect]
        let viewport: CGRect
        let content: CGRect
    }

    struct Source {
        let id: ID
        let measurement: Measurement
        let destination: Mode
        let focus: Target?

        var visibleFrames: [Target: CGRect] {
            measurement.frames.filter { $0.value.intersects(measurement.viewport) }
        }
    }

    struct Tile: Identifiable {
        enum Visibility: Equatable {
            case source
            case destination
            case both
        }

        let id: Target
        let source: CGRect
        let destination: CGRect
        let visibility: Visibility
    }

    struct Plan: Identifiable {
        let source: Source
        let tiles: [Tile]
        var id: ID {
            source.id
        }
    }

    enum Phase {
        case preparing(Source)
        case moving(Plan)

        var source: Source {
            switch self {
                case let .preparing(source): source
                case let .moving(plan): plan.source
            }
        }
    }

    private(set) var phase: Phase?
    // Geometry changes on every scroll frame. Cache it without invalidating the
    // calendar body; only starting or finishing a transition changes presentation.
    @ObservationIgnored private(set) var measurement: Measurement?
    private var sequence = 0

    func updateMeasurement(_ measurement: Measurement?) {
        self.measurement = measurement
        if let measurement { resolve(destination: measurement) }
    }

    func begin(from measurement: Measurement, to destination: Mode, focus: Target?) {
        guard phase == nil, measurement.mode != destination,
              measurement.frames.values.contains(where: { $0.intersects(measurement.viewport) })
        else { return }
        sequence += 1
        phase = .preparing(Source(
            id: ID(rawValue: sequence),
            measurement: measurement,
            destination: destination,
            focus: focus,
        ))
    }

    func resolve(destination: Measurement) {
        guard let source = phase?.source,
              destination.mode == source.destination
        else { return }
        guard abs(destination.viewport.width - source.measurement.viewport.width) < Self
            .geometryTolerance,
            abs(destination.viewport.height - source.measurement.viewport.height) < Self
            .geometryTolerance
        else {
            cancel()
            return
        }
        guard case .preparing = phase, !destination.frames.isEmpty else { return }

        switch source.destination {
            case .overview:
                guard abs(destination.content.minY) < Self.geometryTolerance else { return }
            case .detail:
                guard let focus = source.focus, let frame = destination.frames[focus],
                      frame.intersects(destination.viewport),
                      abs(frame.minY) < Self.geometryTolerance
                      || destination.content.maxY <= destination.viewport.maxY + Self
                      .geometryTolerance
                else { return }
        }

        let shared = source.measurement.frames.keys.filter { destination.frames[$0] != nil }
        let anchor = source.focus.flatMap { shared.contains($0) ? $0 : nil }
            ?? shared.max {
                visibleArea(source.measurement.frames[$0], in: source.measurement.viewport)
                    < visibleArea(source.measurement.frames[$1], in: source.measurement.viewport)
            }
        guard let anchor,
              let sourceAnchor = source.measurement.frames[anchor],
              let destinationAnchor = destination.frames[anchor],
              sourceAnchor.width > 0, destinationAnchor.width > 0
        else {
            cancel()
            return
        }

        let sourceTargets = Set(source.visibleFrames.keys)
        let destinationTargets = Set(destination.frames.filter {
            $0.value.intersects(destination.viewport)
        }.keys)
        let targets = sourceTargets.union(destinationTargets)
        let tiles = targets.sorted(by: Self.ordered).compactMap { target -> Tile? in
            let from = Self.frame(
                for: target,
                in: source.measurement,
                other: destination,
                anchor: sourceAnchor,
                otherAnchor: destinationAnchor,
            )
            let to = Self.frame(
                for: target,
                in: destination,
                other: source.measurement,
                anchor: destinationAnchor,
                otherAnchor: sourceAnchor,
            )
            guard let from, let to, from.width > 0, from.height > 0,
                  to.width > 0, to.height > 0 else { return nil }
            // A projected frame can cross the viewport even when its real tile
            // is offscreen. Render only the copies that belong to each endpoint.
            let visibility: Tile.Visibility = sourceTargets.contains(target)
                ? (destinationTargets.contains(target) ? .both : .source) : .destination
            return Tile(id: target, source: from, destination: to, visibility: visibility)
        }
        phase = .moving(Plan(source: source, tiles: tiles))
    }

    func finish(_ id: ID) -> Bool {
        guard phase?.source.id == id else { return false }
        phase = nil
        return true
    }

    func cancel() {
        phase = nil
    }

    /// Match visible counterparts exactly. Other months continue the selected
    /// month's scale and translation instead of flying through the entire year.
    /// An offscreen estimate enters or leaves below the viewport at full width.
    private static func frame(
        for target: Target,
        in measurement: Measurement,
        other: Measurement,
        anchor: CGRect,
        otherAnchor: CGRect,
    ) -> CGRect? {
        if let frame = measurement.frames[target], frame.intersects(measurement.viewport) {
            return frame
        }
        guard let otherFrame = other.frames[target] else { return nil }
        switch target {
            case .month:
                return project(otherFrame, from: otherAnchor, to: anchor)
            case .estimate:
                let frame = measurement.frames[target] ?? otherFrame
                return CGRect(
                    x: frame.minX,
                    y: measurement.viewport.maxY,
                    width: frame.width,
                    height: frame.height,
                )
        }
    }

    private static func project(_ frame: CGRect, from: CGRect, to: CGRect) -> CGRect {
        let scale = to.width / from.width
        return CGRect(
            x: to.midX + (frame.midX - from.midX) * scale - frame.width * scale / 2,
            y: to.midY + (frame.midY - from.midY) * scale - frame.height * scale / 2,
            width: frame.width * scale,
            height: frame.height * scale,
        )
    }

    private func visibleArea(_ frame: CGRect?, in viewport: CGRect) -> CGFloat {
        guard let frame else { return 0 }
        let visible = frame.intersection(viewport)
        return visible.isNull ? 0 : visible.width * visible.height
    }

    static func ordered(_ lhs: Target, _ rhs: Target) -> Bool {
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        switch (lhs, rhs) {
            case (.month, .estimate): return true
            case (.month, .month), (.estimate, .month), (.estimate, .estimate): return false
        }
    }
}
