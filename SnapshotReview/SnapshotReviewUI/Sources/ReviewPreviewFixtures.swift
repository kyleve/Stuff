#if DEBUG
    import Foundation
    import SnapshotReviewCore
    import UIKit

    @MainActor enum ReviewPreviewFixtures {
        static func model(loaded: Bool = false, single: Bool = false) -> ReviewBrowserModel {
            let model = ReviewBrowserModel(storage: PreviewStorage(), preferences: UserDefaults())
            guard loaded else { return model }
            let root = URL(fileURLWithPath: "/preview")
            let suite = root.appendingPathComponent("__Snapshots__/ProfileTests")
            do {
                let date = Date(timeIntervalSince1970: 1_780_000_000)
                var images: [SnapshotImage] = []
                for frame in ["iPhone", "iPad"] {
                    for variant in [SnapshotVariant.light, .dark] {
                        let path =
                            try SnapshotPath(
                                "profile.Loaded_\(frame)_\(variant.colorScheme.rawValue).png",
                            )
                        let entry = SnapshotManifest.Entry(
                            path: path,
                            testName: "profile",
                            caseName: "Loaded",
                            configurationIdentifier: frame,
                            frame: frame,
                            configurationName: nil,
                            layoutTraits: nil,
                            variant: variant,
                        )
                        images.append(.init(
                            id: .init(suite: suite, path: path),
                            metadata: entry,
                            content: .success(.init(
                                fingerprint: "current",
                                modifiedAt: date,
                                pixels: .init(width: 390, height: 700),
                            )),
                        ))
                    }
                }
                let review = ImageReview(
                    path: images[0].id.path,
                    reviewed: .init(date: date, fingerprint: "current", modifiedAt: date),
                    annotations: [
                        .init(
                            text: "Give the heading more space.",
                            status: .open,
                            point: .init(x: 0.5, y: 0.2),
                            fingerprint: "previous",
                            date: date,
                        ),
                        .init(
                            text: "The grouping is clear.",
                            status: .note,
                            point: nil,
                            fingerprint: "current",
                            date: date,
                        ),
                    ],
                )
                model.installFixture(
                    root: root,
                    suites: [.init(
                        id: suite,
                        name: "ProfileTests",
                        images: images,
                        reviews: .success(.init(document: .init(images: [review]), bytes: nil)),
                        manifestError: nil,
                    )],
                )
                model.select(single ? .image(images[0].id) : .group(model.caseID(images[0])))
                if single {
                    model.displayedImage = .init(imageID: images[0].id, fingerprint: "current")
                }
            } catch { preconditionFailure("Invalid preview fixture: \(error)") }
            return model
        }

        static func bitmap() -> CGImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(
                size: CGSize(width: 390, height: 700),
                format: format,
            ).image { context in
                UIColor.systemGroupedBackground.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 390, height: 700))
                let title: NSString = "Your profile"
                title.draw(
                    at: CGPoint(x: 24, y: 100),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 32, weight: .bold),
                        .foregroundColor: UIColor.label,
                    ],
                )
                for (index, label) in ["Personal details", "Notifications", "Appearance", "Privacy"]
                    .enumerated()
                {
                    let y = 180 + CGFloat(index) * 80
                    UIColor.secondarySystemGroupedBackground.setFill()
                    UIBezierPath(
                        roundedRect: CGRect(x: 20, y: y, width: 350, height: 64),
                        cornerRadius: 12,
                    ).fill()
                    (label as NSString).draw(
                        at: CGPoint(x: 36, y: y + 22),
                        withAttributes: [
                            .font: UIFont.systemFont(ofSize: 17),
                            .foregroundColor: UIColor.label,
                        ],
                    )
                }
            }
            guard let bitmap = image.cgImage else { preconditionFailure("Fixture image missing") }
            return bitmap
        }

        private actor PreviewStorage: ReviewWorkspaceStorage {
            func scan(root _: URL) -> [SnapshotSuite] {
                []
            }

            func save(
                _: ReviewDocument,
                suite _: URL,
                expected _: Data?,
                image _: SnapshotImage,
            ) throws -> ReviewFile {
                throw ReviewError.unavailableImage("Preview records are read-only.")
            }
        }
    }

    actor ReviewPreviewImageLoader: ReviewImageLoading {
        private let bitmap: CGImage
        private var loads = 0
        init(bitmap: CGImage) {
            self.bitmap = bitmap
        }

        func image(_: SnapshotImage, thumbnail _: Bool) -> CGImage {
            loads += 1; return bitmap
        }

        func waitForLoads(_ expected: Int) async {
            while loads < expected, !Task.isCancelled {
                await Task.yield()
            }
        }
    }
#endif
