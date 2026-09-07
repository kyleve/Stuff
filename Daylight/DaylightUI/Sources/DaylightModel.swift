import DaylightCore
import DaylightMastodon
import Foundation
import Observation
import UIKit

/// Observable presentation state. Services own capture, persistence, and delivery behavior.
@MainActor @Observable
public final class DaylightModel {
    public enum Mode: Equatable { case setup, armed, suspended(String) }
    public var settings = CaptureSettings.standard
    public var account = MastodonSettings.initial
    public var server = ""
    public var token = ""
    public private(set) var mode: Mode = .setup
    public private(set) var manualHistory: [ManualCapture] = []
    public private(set) var history: [CaptureSequence] = []
    public private(set) var nextCapture: Date?
    public private(set) var lenses: [CaptureSettings.Camera.Lens] = [.main]
    public private(set) var previewImage: UIImage?
    public private(set) var notice: String?
    public private(set) var ready = false
    public private(set) var working = false
    private struct RunID: Equatable { let rawValue = UUID() }
    private struct CameraStop { let id: RunID; let task: Task<Void, Never> }
    private var currentRun: RunID?
    private var armRevision = RunID()
    private var cameraStop: CameraStop?
    private let readiness: any CaptureReadiness
    private let engine: any CaptureControlling
    private let camera: any CameraCapturing
    private let photos: any PhotosSaving
    private let mastodon: any MastodonManaging
    private var screen: UIScreen?
    private var previousBrightness: CGFloat?
    private var previousIdleDisabled: Bool?

    public init(
        engine: any CaptureControlling,
        camera: any CameraCapturing,
        photos: any PhotosSaving,
        mastodon: any MastodonManaging,
        readiness: any CaptureReadiness,
    ) {
        self.readiness = readiness
        self.engine = engine; self.camera = camera; self.photos = photos; self.mastodon = mastodon
    }

    public var isArmed: Bool {
        switch mode { case .setup: false; case .armed, .suspended: true }
    }

    public var previewKey: PreviewKey {
        PreviewKey(
            settings: settings.camera,
            enabled: !isArmed && !working,
        )
    }

    public struct PreviewKey: Equatable { let settings: CaptureSettings.Camera; let enabled: Bool }
    public var recentHistory: [CaptureSequence] {
        Array(history
            .filter {
                !$0.images.isEmpty || $0.slots
                    .contains {
                        switch $0
                            .state { case .failed, .missed: true; case .pending, .capturing,
                                 .captured: false }
                    }
            }.prefix(14))
    }

    public func load() async {
        guard !ready else { return }
        do {
            settings = try await engine.load()
            if try await engine.armedIntent() { mode = .armed }
            account = await mastodon.configuration()
            server = account.connection?.server.absoluteString ?? ""
            lenses = await camera.availableLenses()
            try await engine.plan()
            await refresh()
            manualHistory = try await engine.manualHistory()
            ready = true
        } catch { notice = error.localizedDescription }
    }

    public func saveSettings() async {
        guard !working else { return }
        working = true; defer { working = false }
        do {
            try await engine.configure(settings); try await engine
                .plan(); await refresh(); notice = nil
        } catch { notice = error.localizedDescription }
    }

    public func toggleArmed() async {
        guard !working else { return }
        working = true; defer { working = false }
        armRevision = RunID()
        if isArmed {
            do { try await engine.setArmedIntent(false) }
            catch { notice = error.localizedDescription; return }
            mode = .setup; await stopCamera(); restoreScreen(); return
        }
        do {
            try await engine.configure(settings)
            guard await camera.requestAccess() else { throw DaylightError.cameraPermission }
            guard await photos.requestAccess() else { throw DaylightError.photosPermission }
            await stopCamera()
            try await engine.setArmedIntent(true)
            mode = .armed; notice = nil
            dimScreen()
        } catch { notice = error.localizedDescription }
    }

    public func testShot() async {
        guard !working, !isArmed else { return }
        working = true; defer { working = false }
        do {
            try await engine.configure(settings)
            guard await camera.requestAccess() else { throw DaylightError.cameraPermission }
            guard await photos.requestAccess() else { throw DaylightError.photosPermission }
            await stopCamera()
            try await engine.manualCapture()
            manualHistory = try await engine.manualHistory()
            notice = String(localized: .captureTestSaved)
        } catch { notice = error.localizedDescription }
    }

    public func connect() async {
        guard !working else { return }
        working = true; defer { working = false }
        do {
            account = try await mastodon
                .connect(server: server, token: token); token = ""; notice = nil
        } catch { notice = error.localizedDescription }
    }

    public func savePublishing() async {
        do { try await mastodon.update(
            enabled: account.enabled,
            visibility: account.visibility,
            caption: account.caption,
        ); notice = nil } catch {
            notice = error.localizedDescription; account = await mastodon.configuration()
        }
    }

    public func preview() async {
        guard previewKey.enabled else { return }
        await cameraStop?.task.value
        guard await camera.requestAccess()
        else { notice = DaylightError.cameraPermission.localizedDescription; return }
        do {
            await cameraStop?.task.value
            try Task.checkCancellation()
            guard previewKey.enabled else { return }
            let stream = try await camera.preview(
                settings: settings.camera,
            )
            for try await data in stream {
                guard !Task.isCancelled else { return }
                previewImage = UIImage(data: data)
            }
        } catch is CancellationError { return }
        catch { if !Task.isCancelled { notice = error.localizedDescription } }
    }

    /// Stop requests are owned tasks: newer sessions wait for a stop already in flight.
    private func stopCamera() async {
        let previous = cameraStop?.task
        let operation = CameraStop(id: RunID(), task: Task { [camera] in
            await previous?.value
            await camera.stop()
        })
        cameraStop = operation
        await operation.task.value
        if cameraStop?.id == operation.id { cameraStop = nil }
    }

    public func run(active: Bool) async {
        let run = RunID()
        currentRun = run
        guard active else { restoreScreen(); await stopCamera(); return }
        await cameraStop?.task.value
        guard currentRun == run, !Task.isCancelled else { return }
        await load()
        guard ready, currentRun == run, !Task.isCancelled else { return }
        if isArmed { dimScreen() }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.captureLoop(run: run) }
            group.addTask { await self.publishingLoop(run: run) }
            await group.waitForAll()
        }
        guard currentRun == run else { return }
        await stopCamera()
        guard currentRun == run else { return }
        restoreScreen()
    }

    private func captureLoop(run: RunID) async {
        while currentRun == run, !Task.isCancelled {
            let revision = armRevision
            do {
                if isArmed {
                    try readiness.check()
                    try await engine.tick(canCapture: true)
                    guard currentRun == run, !Task.isCancelled else { return }
                    if armRevision == revision, isArmed { mode = .armed }
                } else { try await engine.tick(canCapture: false) }
                guard currentRun == run, !Task.isCancelled else { return }
                await refresh()
                try await Task.sleep(for: .seconds(1))
            } catch is CancellationError { return }
            catch {
                guard currentRun == run, !Task.isCancelled else { return }
                if armRevision == revision {
                    if isArmed { mode = .suspended(error.localizedDescription) }
                    else { notice = error.localizedDescription }
                }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }

    private func publishingLoop(run: RunID) async {
        while currentRun == run, !Task.isCancelled {
            do { try await engine.publishPending(); try await Task.sleep(for: .seconds(5)) }
            catch is CancellationError { return }
            catch {
                guard currentRun == run, !Task.isCancelled else { return }
                notice = error.localizedDescription
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    private func refresh() async {
        history = await engine.history(); nextCapture = await engine.nextCapture()
        do { manualHistory = try await engine.manualHistory() }
        catch { notice = error.localizedDescription }
    }

    func attachScreen(_ screen: UIScreen) {
        if self.screen !== screen { restoreScreen(); self.screen = screen }
        if isArmed { dimScreen() }
    }

    private func dimScreen() {
        guard let screen, previousBrightness == nil else { return }
        previousBrightness = screen.brightness
        previousIdleDisabled = UIApplication.shared.isIdleTimerDisabled
        screen.brightness = 0.05
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func restoreScreen() {
        if let previousBrightness {
            screen?.brightness = previousBrightness; self.previousBrightness = nil
        }
        if let previousIdleDisabled {
            UIApplication.shared.isIdleTimerDisabled = previousIdleDisabled; self
                .previousIdleDisabled = nil
        }
    }
}

#if DEBUG
    extension DaylightModel {
        static func preview(mode: Mode, notice: String?) -> DaylightModel {
            let model = DaylightPreviewSupport.model()
            model.ready = true
            model.mode = mode
            model.notice = notice
            model.history = [DaylightPreviewSupport.sequence()]
            model.nextCapture = Date(timeIntervalSince1970: 1_788_789_900)
            return model
        }
    }
#endif
