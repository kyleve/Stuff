import DaylightCore
@testable import DaylightUI
import Foundation
import Testing
import UIKit

@MainActor
struct DaylightModelTests {
    @Test func loadsFromInjectedServicesAndPersistsSettings() async {
        let model = DaylightPreviewSupport.model()
        await model.load()
        #expect(model.ready)
        #expect(model.history.count == 1)
        #expect(!model.isArmed)
        model.settings.camera.zoom = 2
        await model.saveSettings()
        #expect(model.notice == nil)
    }

    @Test func previewRequestsPermissionAndShowsFramesBeforeArchiveLoads() async {
        let frame = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let camera = PreviewTestCamera(allowed: true, frame: frame)
        let model = DaylightModel(
            engine: PreviewCaptureController(),
            camera: camera,
            photos: PreviewPhotos(),
            mastodon: PreviewAccount(),
            readiness: PreviewReadiness(),
        )
        #expect(!model.ready)
        await model.preview()
        #expect(await camera.accessRequests == 1)
        #expect(await camera.previewStarts == 1)
        #expect(model.previewImage != nil)
        #expect(model.notice == nil)
    }

    @Test func deniedCameraAccessShowsFailureWithoutStartingPreview() async {
        let camera = PreviewTestCamera(allowed: false, frame: Data())
        let model = DaylightModel(
            engine: PreviewCaptureController(),
            camera: camera,
            photos: PreviewPhotos(),
            mastodon: PreviewAccount(),
            readiness: PreviewReadiness(),
        )
        await model.preview()
        #expect(await camera.accessRequests == 1)
        #expect(await camera.previewStarts == 0)
        #expect(model.notice == DaylightError.cameraPermission.localizedDescription)
    }

    @Test func cancelledPreviewDoesNotStartAfterPermissionResponse() async {
        let camera = PreviewTestCamera(allowed: true, frame: Data())
        let model = DaylightModel(
            engine: PreviewCaptureController(),
            camera: camera,
            photos: PreviewPhotos(),
            mastodon: PreviewAccount(),
            readiness: PreviewReadiness(),
        )
        let task = Task { await model.preview() }
        task.cancel()
        await task.value
        #expect(await camera.previewStarts == 0)
    }

    @Test func stoppingReturnsToSetup() async {
        let model = DaylightModel.preview(mode: .armed, notice: nil)
        await model.toggleArmed()
        #expect(!model.isArmed)
    }
}

extension DaylightModelTests {
    @Test(.timeLimit(.minutes(1))) func stoppingDuringTickCannotRearm() async {
        let engine = LifecycleTestController(blockTick: true, blockPublishing: false)
        let model = DaylightModel(
            engine: engine,
            camera: PreviewTestCamera(allowed: true, frame: Data()),
            photos: PreviewPhotos(),
            mastodon: PreviewAccount(),
            readiness: PreviewReadiness(),
        )
        let run = Task { await model.run(active: true) }
        await engine.tickEntered.wait()
        await model.toggleArmed()
        #expect(!model.isArmed)
        await engine.releaseTick.open()
        await engine.nextTick.wait()
        #expect(!model.isArmed)
        #expect(await engine.armedIntent() == false)
        run.cancel(); await run.value
    }

    @Test(.timeLimit(.minutes(1))) func previousForegroundCleanupCannotStopCurrentCamera() async {
        let engine = LifecycleTestController(blockTick: false, blockPublishing: true)
        let camera = PreviewTestCamera(allowed: true, frame: Data())
        let model = DaylightModel(
            engine: engine,
            camera: camera,
            photos: PreviewPhotos(),
            mastodon: PreviewAccount(),
            readiness: PreviewReadiness(),
        )
        let oldRun = Task { await model.run(active: true) }
        await engine.publishingEntered.wait()
        oldRun.cancel()
        await model.run(active: false)
        let stops = await camera.stops
        let newRun = Task { await model.run(active: true) }
        await engine.nextTick.wait()
        await engine.releasePublishing.open()
        await oldRun.value
        #expect(await camera.stops == stops)
        #expect(model.isArmed)
        newRun.cancel(); await newRun.value
    }
}
