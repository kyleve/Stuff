import Foundation

public protocol CameraCapturing: Sendable {
    func requestAccess() async -> Bool
    func availableLenses() async -> [CaptureSettings.Camera.Lens]
    func capture(settings: CaptureSettings.Camera) async throws -> Data
    func preview(settings: CaptureSettings.Camera, recipe: ImageRecipe) async throws
        -> AsyncThrowingStream<Data, any Error>
    func stop() async
}
