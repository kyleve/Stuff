import Foundation

public protocol CaptureControlling: Sendable {
    func armedIntent() async throws -> Bool
    func setArmedIntent(_ armed: Bool) async throws
    func load() async throws -> CaptureSettings
    func configure(_ settings: CaptureSettings) async throws
    func plan() async throws
    func tick(canCapture: Bool) async throws
    func publishPending() async throws
    func history() async -> [CaptureSequence]
    func nextCapture() async -> Date?
    func manualHistory() async throws -> [ManualCapture]
    func manualCapture() async throws
}
