#if DEBUG
    import DaylightCore
    import DaylightMastodon
    import Foundation

    @MainActor
    enum DaylightPreviewSupport {
        static func model() -> DaylightModel {
            DaylightModel(
                engine: PreviewCaptureController(),
                camera: PreviewCamera(),
                photos: PreviewPhotos(),
                mastodon: PreviewAccount(),
            )
        }

        static func completedSequence() -> CaptureSequence {
            var result = sequence()
            for index in 7 ..< result.slots.count {
                result.slots[index].state = .missed
            }
            let image = result.images[6]
            result.selection = .selected(image.id)
            var delivery = PublishingDelivery(
                destination: PublishingDestinationID(rawValue: "mastodon"),
                imageID: image.id,
                kind: .sequenceHighlight,
            )
            delivery.state = .delivered(PublishingReceipt(
                remoteID: "example",
                url: URL(string: "https://example.com/@daylight/1")!,
            ))
            result.deliveries = [delivery]
            return result
        }

        static func sequence() -> CaptureSequence {
            var sequence = CaptureSequence(
                event: SolarEvent(
                    id: .init(year: 2026, month: 9, day: 7, kind: .sunrise),
                    date: Date(timeIntervalSince1970: 1_788_789_600),
                ),
                settings: .standard,
            )
            for index in 0 ..< 7 {
                var image = CapturedImage(
                    id: sequence.slots[index].id,
                    capturedAt: sequence.slots[index].scheduledAt,
                    format: .jpeg,
                )
                image.photos = .saved("preview-\(index)")
                image.score = .scored(.init(overall: 0.5, isUtility: false))
                sequence.slots[index].state = .captured(image)
            }
            return sequence
        }
    }

    actor PreviewCaptureController: CaptureControlling {
        func armedIntent() -> Bool {
            false
        }

        func setArmedIntent(_: Bool) {}
        func load() -> CaptureSettings {
            .standard
        }

        func configure(_: CaptureSettings) {}
        func plan() {}
        func tick(canCapture _: Bool) {}
        func publishPending() {}
        func history() async -> [CaptureSequence] {
            await [DaylightPreviewSupport.sequence()]
        }

        func nextCapture() -> Date? {
            Date(timeIntervalSince1970: 1_788_789_900)
        }

        func manualHistory() -> [ManualCapture] {
            []
        }

        func manualCapture() {}
    }

    private struct PreviewCamera: CameraCapturing {
        func requestAccess() -> Bool {
            true
        }

        func availableLenses() -> [CaptureSettings.Camera.Lens] {
            [.main, .ultraWide]
        }

        func capture(settings _: CaptureSettings.Camera) throws -> CameraCapture {
            throw DaylightError
                .unavailableCamera
        }

        func preview(
            settings _: CaptureSettings.Camera,
        )
            -> AsyncThrowingStream<Data, any Error>
        {
            AsyncThrowingStream { $0.finish() }
        }

        func stop() {}
    }

    struct PreviewPhotos: PhotosSaving {
        func requestAccess() -> Bool {
            true
        }

        func contains(assetIdentifier _: String) -> Bool {
            true
        }

        func save(
            originalURL _: URL,
            rawURL _: URL?,
            capturedAt _: Date,
            recordIdentifier _: @escaping @Sendable (String) async throws -> Void,
        ) -> String {
            "preview"
        }
    }

    actor PreviewAccount: MastodonManaging {
        var settings = MastodonSettings.initial
        func configuration() -> MastodonSettings {
            settings
        }

        func connect(server _: String, token _: String) -> MastodonSettings {
            settings
        }

        func update(enabled: Bool, visibility: MastodonSettings.Visibility, caption: String) {
            settings.enabled = enabled; settings.visibility = visibility; settings.caption = caption
        }
    }
#endif
