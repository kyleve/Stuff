#if DEBUG
    @testable import Flyover
    import Foundation
    import SnapshotKit
    import SwiftUI
    import Testing

    @MainActor
    struct FlyoverWebExporterTests {
        @Test func writesAStableManifestAndEveryRequestedImage() async throws {
            var resetCount = 0
            let catalog = makeCatalog(reset: { resetCount += 1 })
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let exporter = FlyoverWebExporter(
                catalog: catalog,
                applicationID: "test-app",
                title: "Test </script> App",
                screenIdentifier: \FlyoverTestScreen.rawValue,
            )

            let summary = try await exporter.export(
                to: directory,
                profiles: [.phoneLight, .phoneDark, .phoneLight],
                build: build,
            ) { request in
                FlyoverCapturedImage(
                    pngData: Data([0x89, 0x50, 0x4E, 0x47]),
                    pointSize: request.configuration.device.testPointSize,
                    pixelSize: CGSize(width: 1206, height: 2622),
                    scale: 3,
                )
            }

            #expect(summary.screenCount == 3)
            #expect(summary.stateCount == 4)
            #expect(summary.profileCount == 2)
            #expect(summary.imageCount == 8)
            #expect(resetCount == 4)

            let data = try Data(contentsOf: directory.appending(path: "manifest.json"))
            let manifest = try JSONDecoder().decode(FlyoverWebManifest.self, from: data)
            #expect(manifest.schemaVersion == 1)
            #expect(manifest.application.id == "test-app")
            #expect(manifest.application.title == "Test </script> App")
            #expect(manifest.groups.map(\.id) == ["main"])
            #expect(manifest.screens.map(\.id) == ["root", "pushed", "modal"])
            #expect(manifest.routes.map(\.id) == ["route-0001", "route-0002"])
            #expect(manifest.images.count == 8)
            #expect(manifest.images.allSatisfy { image in
                image.relativePath.hasPrefix("images/screen-")
                    && image.relativePath.hasPrefix("/") == false
                    && FileManager.default.fileExists(
                        atPath: directory.appending(path: image.relativePath).path,
                    )
            })
            let script = try String(
                contentsOf: directory.appending(path: "manifest.js"),
                encoding: .utf8,
            )
            #expect(script.hasPrefix("window.FLYOVER_MANIFEST = {"))
        }

        @Test func validatesEverySizingPolicyBeforeTheFirstCapture() async throws {
            let mixed = SnapshotCase(
                name: "Mixed",
                configurations: [
                    SnapshotConfiguration(device: .iPhone),
                    SnapshotConfiguration(device: .iPhoneFullContent),
                ],
            ) {
                EmptyView()
            }
            let screen = FlyoverScreen(
                id: FlyoverTestScreen.root,
                title: "Root",
                variants: [FlyoverVariant(id: FlyoverVariantID("mixed"), snapshotCase: mixed)],
            )
            let catalog = FlyoverCatalog(groups: [
                FlyoverGroup(
                    id: FlyoverGroupID("main"),
                    title: "Main",
                    root: .root,
                    screens: [screen],
                ),
            ])
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            var captureCount = 0
            let exporter = FlyoverWebExporter(
                catalog: catalog,
                applicationID: "test",
                title: "Test",
                screenIdentifier: \FlyoverTestScreen.rawValue,
            )

            do {
                _ = try await exporter.export(
                    to: directory,
                    profiles: [.phoneLight],
                    build: build,
                ) { _ in
                    captureCount += 1
                    return FlyoverCapturedImage(
                        pngData: Data([1]),
                        pointSize: CGSize(width: 1, height: 1),
                        pixelSize: CGSize(width: 1, height: 1),
                        scale: 1,
                    )
                }
                Issue.record("Expected mixed sizing to fail export planning.")
            } catch let error as FlyoverExportError {
                #expect(error == .mixedSizingPolicy(
                    screen: "root",
                    variant: "mixed",
                    extents: ["fullContent", "viewport"],
                ))
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
            #expect(captureCount == 0)
        }

        @Test func rejectsDuplicateStableScreenIdentifiers() async throws {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let exporter = FlyoverWebExporter(
                catalog: makeCatalog(),
                applicationID: "test",
                title: "Test",
                screenIdentifier: { _ in "duplicate" },
            )

            do {
                _ = try await exporter.export(
                    to: directory,
                    profiles: [.phoneLight],
                    build: build,
                ) { _ in
                    Issue.record("Capture must not run after validation fails.")
                    return FlyoverCapturedImage(
                        pngData: Data([1]),
                        pointSize: .zero,
                        pixelSize: .zero,
                        scale: 1,
                    )
                }
                Issue.record("Expected duplicate identifiers to fail.")
            } catch let error as FlyoverExportError {
                #expect(error == .duplicateScreenIdentifier("duplicate"))
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }

        @Test func cancellationAfterCaptureDoesNotPublishTheImageOrManifest() async throws {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let screen = makeFlyoverTestScreen(.root, title: "Root")
            let catalog = FlyoverCatalog(groups: [
                FlyoverGroup(
                    id: FlyoverGroupID("main"),
                    title: "Main",
                    root: .root,
                    screens: [screen],
                ),
            ])
            let exporter = FlyoverWebExporter(
                catalog: catalog,
                applicationID: "test",
                title: "Test",
                screenIdentifier: \FlyoverTestScreen.rawValue,
            )

            let export = Task { @MainActor in
                try await exporter.export(
                    to: directory,
                    profiles: [.phoneLight],
                    build: build,
                ) { _ in
                    withUnsafeCurrentTask { task in task?.cancel() }
                    return FlyoverCapturedImage(
                        pngData: Data([1]),
                        pointSize: CGSize(width: 1, height: 1),
                        pixelSize: CGSize(width: 1, height: 1),
                        scale: 1,
                    )
                }
            }

            await #expect(throws: CancellationError.self) {
                try await export.value
            }
            #expect(FileManager.default.fileExists(
                atPath: directory.appending(path: "manifest.json").path,
            ) == false)
            #expect(try pngCount(in: directory) == 0)
        }

        private var build: FlyoverExportBuild {
            FlyoverExportBuild(
                commit: "abc123",
                dirty: false,
                branch: "tests",
                generatedAt: "2026-08-13T12:00:00Z",
                xcodeVersion: "Xcode 27.0",
                simulatorDevice: "iPhone 17",
                simulatorOS: "27.0",
            )
        }

        private func makeCatalog(
            reset: @escaping @MainActor () -> Void = {},
        ) -> FlyoverCatalog<FlyoverTestScreen> {
            FlyoverCatalog(
                groups: [
                    FlyoverGroup(
                        id: FlyoverGroupID("main"),
                        title: "Main",
                        root: .root,
                        screens: [
                            FlyoverScreen(
                                id: FlyoverTestScreen.root,
                                title: "Root",
                                variants: [
                                    FlyoverVariant(
                                        id: FlyoverVariantID("default"),
                                        title: "Default",
                                    ) { Text("Root") },
                                    FlyoverVariant(
                                        id: FlyoverVariantID("empty"),
                                        title: "Empty",
                                    ) { EmptyView() },
                                ],
                                reset: reset,
                            ),
                            makeFlyoverTestScreen(.pushed, title: "Pushed"),
                            makeFlyoverTestScreen(.modal, title: "Modal"),
                        ],
                    ),
                ],
                transitions: [
                    FlyoverTransition(from: .root, to: .pushed, kind: .push),
                    FlyoverTransition(from: .root, to: .modal, kind: .modal),
                ],
            )
        }

        private func makeTemporaryDirectory() throws -> URL {
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "FlyoverWebExporterTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
            )
            return directory
        }

        private func pngCount(in directory: URL) throws -> Int {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
            ) else {
                return 0
            }
            return enumerator.compactMap { $0 as? URL }
                .count(where: { $0.pathExtension == "png" })
        }
    }

    extension SnapshotConfiguration.Frame {
        fileprivate var testPointSize: CGSize {
            switch size {
                case let .fixed(size): size
                case let .intrinsic(width): CGSize(width: width ?? 402, height: 1)
                case let .fullContent(width, minimumHeight):
                    CGSize(width: width, height: minimumHeight ?? 1)
                case let .fullContent2D(minimumSize): minimumSize
            }
        }
    }
#endif
