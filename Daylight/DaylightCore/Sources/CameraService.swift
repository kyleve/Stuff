import AVFoundation
import Foundation

/// AVFoundation is confined to a serial executor, including blocking session startup/shutdown.
public actor CameraService: CameraCapturing {
    private let queue = DispatchSerialQueue(label: "com.stuff.daylight.camera")
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    private let session = AVCaptureSession()
    private let photos = AVCapturePhotoOutput()
    private let video = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var photoDelegate: PhotoCaptureDelegate?
    private var previewToken: UUID?
    private var previewDelegate: PreviewCaptureDelegate?
    public init() {}

    public func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    public func availableLenses() -> [CaptureSettings.Camera.Lens] {
        CaptureSettings.Camera.Lens.allCases.filter { camera(for: $0) != nil }
    }

    private func camera(for lens: CaptureSettings.Camera.Lens) -> AVCaptureDevice? {
        let type: AVCaptureDevice.DeviceType
        switch lens {
            case .main: type = .builtInWideAngleCamera; case .ultraWide: type =
            .builtInUltraWideCamera; case .telephoto: type = .builtInTelephotoCamera
        }
        return AVCaptureDevice.default(type, for: .video, position: .back)
    }

    private func configure(_ settings: CaptureSettings.Camera, preview: Bool) throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        else { throw DaylightError.cameraPermission }
        guard let camera = camera(for: settings.lens) else { throw DaylightError.unavailableCamera }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        for input in session.inputs {
            session.removeInput(input)
        }
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw DaylightError.unavailableCamera }
        session.addInput(input)
        if !session.outputs.contains(photos) {
            guard session.canAddOutput(photos) else { throw DaylightError.unavailableCamera }
            session.addOutput(photos)
        }
        photos.isAppleProRAWEnabled = photos.isAppleProRAWSupported
        if session.outputs.contains(video) { session.removeOutput(video) }
        if preview {
            video.alwaysDiscardsLateVideoFrames = true
            guard session.canAddOutput(video) else { throw DaylightError.unavailableCamera }
            session.addOutput(video)
            video.setSampleBufferDelegate(previewDelegate, queue: queue)
        }
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }
        camera.videoZoomFactor = min(
            camera.maxAvailableVideoZoomFactor,
            max(camera.minAvailableVideoZoomFactor, settings.zoom),
        )
        camera.setExposureTargetBias(min(
            camera.maxExposureTargetBias,
            max(camera.minExposureTargetBias, settings.exposureBias),
        ))
        if camera
            .isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
        if camera
            .isExposureModeSupported(.continuousAutoExposure)
        {
            camera.exposureMode = .continuousAutoExposure
        }
        if camera
            .isWhiteBalanceModeSupported(.continuousAutoWhiteBalance)
        {
            camera.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        // A mounted landscape camera keeps preview and saved frames in the same
        // orientation.
        for output in session.outputs {
            if let connection = output.connection(with: .video),
               connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
        }
        device = camera
    }

    public func capture(settings: CaptureSettings.Camera) async throws -> CameraCapture {
        guard photoDelegate == nil else { throw DaylightError.interrupted }
        previewToken = nil
        previewDelegate?.finish(); previewDelegate = nil
        try configure(settings, preview: false)
        session.startRunning()
        defer { photoDelegate = nil; session.stopRunning() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        repeat {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock
            .now < deadline &&
            (device?.isAdjustingExposure == true || device?.isAdjustingFocus == true || device?
                .isAdjustingWhiteBalance == true)
        guard session.isRunning, !session.isInterrupted else {
            throw DaylightError.interrupted
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let formats = photos.availableRawPhotoPixelFormatTypes
                let rawFormat = formats.first(where: AVCapturePhotoOutput.isAppleProRAWPixelFormat)
                    ??
                    (device?.videoZoomFactor == 1 ? formats
                        .first(where: AVCapturePhotoOutput.isBayerRAWPixelFormat) : nil)
                let delegate = PhotoCaptureDelegate(
                    expectsRAW: rawFormat != nil,
                    continuation: continuation,
                )
                photoDelegate = delegate
                let processed = [AVVideoCodecKey: AVVideoCodecType.jpeg]
                let options: AVCapturePhotoSettings
                if let rawFormat {
                    options = AVCapturePhotoSettings(
                        rawPixelFormatType: rawFormat,
                        processedFormat: processed,
                    )
                    options.photoQualityPrioritization = .speed
                } else { options = AVCapturePhotoSettings(format: processed) }
                options.flashMode = .off
                photos.capturePhoto(with: options, delegate: delegate)
                Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(20)); await self?.timeout(delegate) }
                    catch { delegate.cancel() }
                }
            }
        } onCancel: { Task { await self.cancelCapture() } }
    }

    private func timeout(_ delegate: PhotoCaptureDelegate) {
        if photoDelegate === delegate { delegate.cancel() }
    }

    private func cancelCapture() {
        photoDelegate?.cancel()
    }

    public func preview(
        settings: CaptureSettings.Camera,
    ) throws -> AsyncThrowingStream<Data, any Error> {
        guard photoDelegate == nil else { throw DaylightError.interrupted }
        previewToken = nil
        previewDelegate?.finish()
        let stream = AsyncThrowingStream<Data, any Error>
            .makeStream(bufferingPolicy: .bufferingNewest(1))
        let token = UUID()
        previewToken = token
        stream.continuation
            .onTermination = { [weak self] _ in Task { await self?.endPreview(token) } }
        previewDelegate = PreviewCaptureDelegate(continuation: stream.continuation)
        try configure(settings, preview: true)
        session.startRunning()
        return stream.stream
    }

    private func endPreview(_ token: UUID) {
        guard previewToken == token else { return }
        previewToken = nil
        previewDelegate = nil
        if photoDelegate == nil { session.stopRunning() }
    }

    public func stop() {
        photoDelegate?.cancel()
        previewToken = nil
        previewDelegate?.finish(); previewDelegate = nil
        session.stopRunning()
    }
}
