import DaylightCore
import DaylightMastodon
import DaylightUI
import PeriscopeCore
import SwiftUI

@main
struct DaylightApp: App {
    private let startup: Result<DaylightModel, any Error>
    init() {
        do {
            let root = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true,
            ).appendingPathComponent("Daylight", isDirectory: true)
            let store = try CaptureStore(root: root)
            let camera = CameraService()
            let photos = PhotosLibrary()
            let mastodon = try MastodonDestination(
                settingsURL: root.appendingPathComponent("mastodon.json"),
                transport: URLSessionTransport(),
                credentials: KeychainMastodonCredentials(),
                now: { Date() },
            )
            let logging = Periscope(
                configuration: .init(),
                sinks: [OSLogSink(subsystem: "com.stuff.daylight")],
            )
            let engine = CaptureEngine(
                store: store,
                camera: camera,
                solar: SolarCalculator(),
                photos: photos,
                scorer: VisionImageScorer(),
                destinations: [mastodon],
                log: Log<DaylightLogEvent>(system: logging),
                now: { Date() },
            )
            startup = .success(DaylightModel(
                engine: engine,
                camera: camera,
                photos: photos,
                mastodon: mastodon,
            ))
        } catch { startup = .failure(error) }
    }

    var body: some Scene {
        WindowGroup {
            switch startup {
                case let .success(model): DaylightRootView(model: model)
                case let .failure(error):
                    VStack {
                        Text("Daylight").font(.title); Text(error.localizedDescription).padding()
                    }
            }
        }
    }
}
