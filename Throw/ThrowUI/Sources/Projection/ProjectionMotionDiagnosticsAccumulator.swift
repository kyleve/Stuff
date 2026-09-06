import Foundation
import ThrowCore

/// Reduces render timing and motion into aggregate diagnostics that cannot
/// expose aircraft identities, callsigns, or coordinates.
struct ProjectionMotionDiagnosticsAccumulator {
    private static let reportingInterval: TimeInterval = 10
    private static let detailSampleInterval: TimeInterval = 1

    private var windowStartedAt: Date?
    private var previousFrameAt: Date?
    private var lastDetailSampleAt: Date?
    private var previousTarget: ProjectionFrame?
    private var previousSemanticIDs: Set<LayerMarkID>?
    private var frameIntervalCount = 0
    private var projectedSpeedTotal = 0.0
    private var projectedSpeedCount = 0
    private var correctionDistanceTotal = 0.0
    private var correctionDistanceCount = 0
    private var lastAircraftCount = 0
    private var lastUsableMotionPercent: Double?
    private var lastDerivedMotionPercent: Double?
    private var lastMeanSampleAge: Double?
    private var lastSnapshotRetainedPercent: Double?

    mutating func record(
        layerFrame: ProjectionLayerFrame<FlightsLayerKind>?,
        target: ProjectionFrame,
        at date: Date,
        observationChanged: Bool,
    ) -> ProjectionMotionLogEvent? {
        if windowStartedAt == nil { windowStartedAt = date }
        recordFrameInterval(at: date)
        if needsDetailSample(at: date) {
            recordProjectedSpeeds(target: target)
            recordSemanticState(layerFrame: layerFrame, at: date)
            lastDetailSampleAt = date
        }
        if observationChanged {
            recordSnapshotTransition(layerFrame: layerFrame, target: target)
        }
        previousTarget = target

        guard let windowStartedAt else { return nil }
        let elapsed = date.timeIntervalSince(windowStartedAt)
        guard elapsed >= 0 else {
            resetWindow(startingAt: date)
            return nil
        }
        guard elapsed >= Self.reportingInterval else { return nil }
        guard elapsed.isFinite, elapsed > 0 else {
            resetWindow(startingAt: date)
            return nil
        }
        let event = ProjectionMotionLogEvent(
            framesPerSecond: Double(frameIntervalCount) / elapsed,
            aircraftCount: lastAircraftCount,
            usableHorizontalMotionPercent: lastUsableMotionPercent,
            positionDerivedMotionPercent: lastDerivedMotionPercent,
            meanSampleAgeSeconds: lastMeanSampleAge,
            meanProjectedSpeedPerSecond: mean(
                total: projectedSpeedTotal,
                count: projectedSpeedCount,
            ),
            meanCorrectionDistance: mean(
                total: correctionDistanceTotal,
                count: correctionDistanceCount,
            ),
            previousSnapshotRetainedPercent: lastSnapshotRetainedPercent,
        )
        resetWindow(startingAt: date)
        return event
    }

    private mutating func recordFrameInterval(at date: Date) {
        defer { previousFrameAt = date }
        guard let previousFrameAt else { return }
        let interval = date.timeIntervalSince(previousFrameAt)
        guard interval > 0, interval.isFinite else { return }
        frameIntervalCount += 1
    }

    private func needsDetailSample(at date: Date) -> Bool {
        guard let lastDetailSampleAt else { return true }
        let interval = date.timeIntervalSince(lastDetailSampleAt)
        return interval < 0 || interval >= Self.detailSampleInterval
    }

    private mutating func recordProjectedSpeeds(target: ProjectionFrame) {
        guard let previousTarget, previousTarget.mode == target.mode else { return }
        let interval = target.generatedAt.timeIntervalSince(previousTarget.generatedAt)
        guard interval > 0, interval <= 0.25 else { return }
        let previousByID = previousTarget.marks.reduce(
            into: [LayerMarkID: PresentedMark](),
        ) {
            $0[$1.id] = $1
        }
        for mark in target.marks {
            guard case .aircraft = mark.glyph,
                  let previous = previousByID[mark.id]
            else { continue }
            projectedSpeedTotal += hypot(
                mark.point.x - previous.point.x,
                mark.point.y - previous.point.y,
            ) / interval
            projectedSpeedCount += 1
        }
    }

    private mutating func recordSemanticState(
        layerFrame: ProjectionLayerFrame<FlightsLayerKind>?,
        at date: Date,
    ) {
        let marks = layerFrame?.marks.filter {
            if case .aircraft = $0.glyph { true } else { false }
        } ?? []
        lastAircraftCount = marks.count
        guard marks.isEmpty == false else {
            lastUsableMotionPercent = nil
            lastDerivedMotionPercent = nil
            lastMeanSampleAge = nil
            return
        }
        let usable = marks.filter {
            $0.velocity?.groundTrack != nil && $0.velocity?.groundSpeedKnots != nil
        }
        let derived = usable.filter { $0.velocity?.horizontalSource == .positionDerived }
        lastUsableMotionPercent = Double(usable.count) / Double(marks.count) * 100
        lastDerivedMotionPercent = usable.isEmpty
            ? nil
            : Double(derived.count) / Double(usable.count) * 100
        let ages = marks.map { max(0, date.timeIntervalSince($0.freshness.positionObservedAt)) }
        lastMeanSampleAge = ages.reduce(0, +) / Double(ages.count)
    }

    private mutating func recordSnapshotTransition(
        layerFrame: ProjectionLayerFrame<FlightsLayerKind>?,
        target: ProjectionFrame,
    ) {
        let semanticIDs = Set(layerFrame?.marks.compactMap { mark -> LayerMarkID? in
            guard case .aircraft = mark.glyph else { return nil }
            return presentationID(mark.id)
        } ?? [])
        if let previousSemanticIDs, previousSemanticIDs.isEmpty == false {
            lastSnapshotRetainedPercent = Double(
                previousSemanticIDs.intersection(semanticIDs).count,
            ) / Double(previousSemanticIDs.count) * 100
        }
        previousSemanticIDs = semanticIDs

        guard let previousTarget, previousTarget.mode == target.mode else { return }
        let previousByID = previousTarget.marks.reduce(
            into: [LayerMarkID: PresentedMark](),
        ) {
            $0[$1.id] = $1
        }
        for mark in target.marks {
            guard case .aircraft = mark.glyph,
                  let previous = previousByID[mark.id]
            else { continue }
            correctionDistanceTotal += hypot(
                mark.point.x - previous.point.x,
                mark.point.y - previous.point.y,
            )
            correctionDistanceCount += 1
        }
    }

    private mutating func resetWindow(startingAt date: Date) {
        windowStartedAt = date
        frameIntervalCount = 0
        projectedSpeedTotal = 0
        projectedSpeedCount = 0
        correctionDistanceTotal = 0
        correctionDistanceCount = 0
    }

    private func mean(total: Double, count: Int) -> Double? {
        count > 0 ? total / Double(count) : nil
    }
}
