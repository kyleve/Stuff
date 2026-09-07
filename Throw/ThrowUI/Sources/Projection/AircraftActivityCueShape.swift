import SwiftUI
import ThrowCore

/// Constant-screen-space geometry for ambient flight activity estimates.
struct AircraftActivityCueShape: Shape {
    let stage: FlightActivityStage

    func path(in rect: CGRect) -> Path {
        let half = rect.width / 2
        let near = half * 0.72
        let short = half * 1.35
        let long = half * 2.05
        var path = Path()
        switch stage {
            case .inbound:
                path.move(to: CGPoint(x: -half * 0.62, y: -near))
                path.addLine(to: CGPoint(x: -half * 0.62, y: -short))
                path.addLine(to: CGPoint(x: half * 0.62, y: -short))
                path.addLine(to: CGPoint(x: half * 0.62, y: -near))
            case .approach:
                path.move(to: CGPoint(x: -half * 0.62, y: -near))
                path.addLine(to: CGPoint(x: -half * 1.05, y: -long))
                path.move(to: CGPoint(x: half * 0.62, y: -near))
                path.addLine(to: CGPoint(x: half * 1.05, y: -long))
            case .outbound:
                path.move(to: CGPoint(x: -half * 0.5, y: near))
                path.addLine(to: CGPoint(x: -half * 0.68, y: short))
                path.move(to: CGPoint(x: half * 0.5, y: near))
                path.addLine(to: CGPoint(x: half * 0.68, y: short))
            case .initialClimb:
                path.move(to: CGPoint(x: -half * 0.5, y: near))
                path.addLine(to: CGPoint(x: -half * 1.05, y: long))
                path.move(to: CGPoint(x: half * 0.5, y: near))
                path.addLine(to: CGPoint(x: half * 1.05, y: long))
        }
        return path
    }
}
