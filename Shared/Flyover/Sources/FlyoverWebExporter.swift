#if DEBUG
    import Foundation
    import SwiftUI

    /// Converts a typed Flyover catalog into a static manifest and PNG set.
    @MainActor
    public struct FlyoverWebExporter<ScreenID: Hashable> {
        private let catalog: FlyoverCatalog<ScreenID>
        private let applicationID: String
        private let title: String
        private let screenIdentifier: (ScreenID) -> String

        public init(
            catalog: FlyoverCatalog<ScreenID>,
            applicationID: String,
            title: String,
            screenIdentifier: @escaping (ScreenID) -> String,
        ) {
            self.catalog = catalog
            self.applicationID = applicationID
            self.title = title
            self.screenIdentifier = screenIdentifier
        }

        public func export(
            to directory: URL,
            profiles requestedProfiles: [FlyoverCaptureProfile],
            build: FlyoverExportBuild,
            capture: @escaping (FlyoverCaptureRequest) async throws -> FlyoverCapturedImage,
        ) async throws -> FlyoverExportSummary {
            let profiles = FlyoverCaptureProfile.orderedUnique(requestedProfiles)
            let preparedScreens = try prepareScreens()
            try validatePolicies(in: preparedScreens)
            let layout = FlyoverLayout(catalog: catalog, style: FlyoverStylesheet.default.layout)
                .resolve()
            let preparedRoutes = try prepareRoutes(screens: preparedScreens, layout: layout)

            let fileManager = FileManager.default
            let imagesDirectory = directory.appending(path: "images", directoryHint: .isDirectory)
            do {
                try fileManager.createDirectory(
                    at: imagesDirectory,
                    withIntermediateDirectories: true,
                )
            } catch {
                throw FlyoverExportError.outputWriteFailed(
                    path: imagesDirectory.path,
                    reason: error.localizedDescription,
                )
            }

            var images: [FlyoverWebManifest.Image] = []
            var pathsByVariant: [VariantKey: [String: String]] = [:]
            let captureCount = preparedScreens.reduce(0) { count, prepared in
                count + prepared.screen.variants.count * profiles.count
            }
            var captureIndex = 0

            for prepared in preparedScreens {
                for (variantIndex, variant) in prepared.screen.variants.enumerated() {
                    let policy = try resolvedPolicy(
                        variant,
                        screen: prepared.stableID,
                    )
                    for profile in profiles {
                        try Task.checkCancellation()
                        captureIndex += 1
                        prepared.screen.resetAction()
                        let configuration = profile.configuration(
                            viewport: prepared.screen.viewport,
                            captureExtent: policy.captureExtent,
                        )
                        let relativePath = String(
                            format: "images/screen-%04d/variant-%04d/%@.png",
                            prepared.screenOrdinal,
                            variantIndex + 1,
                            profile.rawValue,
                        )
                        let captureName = "\(prepared.stableID).\(variant.id.rawValue).\(profile.rawValue)"
                        let request = FlyoverCaptureRequest(
                            groupTitle: prepared.groupTitle,
                            screenID: prepared.stableID,
                            screenTitle: prepared.screen.title,
                            variantID: variant.id.rawValue,
                            variantTitle: variant.title,
                            profile: profile,
                            configuration: configuration,
                            policy: policy,
                            captureName: captureName,
                            content: AnyView(FlyoverExportContent(
                                navigationContainer: prepared.screen.navigationContainer,
                                content: variant.overviewContent(),
                            )),
                        )
                        print(
                            "FLYOVER_EXPORT \(captureIndex)/\(captureCount) "
                                +
                                "\(prepared.screen.title) / \(variant.title) / \(profile.rawValue)",
                        )

                        let captured: FlyoverCapturedImage
                        do {
                            captured = try await capture(request)
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            throw FlyoverExportError.captureFailed(
                                group: prepared.groupTitle,
                                screen: prepared.screen.title,
                                variant: variant.title,
                                profile: profile.rawValue,
                                phase: "capture",
                                reason: error.localizedDescription,
                            )
                        }
                        try Task.checkCancellation()
                        guard captured.pngData.isEmpty == false else {
                            throw FlyoverExportError.emptyPNG(
                                screen: prepared.screen.title,
                                variant: variant.title,
                                profile: profile.rawValue,
                            )
                        }

                        let imageURL = directory.appending(path: relativePath)
                        do {
                            try fileManager.createDirectory(
                                at: imageURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true,
                            )
                            try captured.pngData.write(to: imageURL, options: .atomic)
                        } catch {
                            throw FlyoverExportError.outputWriteFailed(
                                path: imageURL.path,
                                reason: error.localizedDescription,
                            )
                        }

                        let key = VariantKey(
                            screenID: prepared.stableID,
                            variantID: variant.id.rawValue,
                        )
                        pathsByVariant[key, default: [:]][profile.rawValue] = relativePath
                        images.append(FlyoverWebManifest.Image(
                            screenID: prepared.stableID,
                            variantID: variant.id.rawValue,
                            profileID: profile.rawValue,
                            relativePath: relativePath,
                            pointWidth: Double(captured.pointSize.width),
                            pointHeight: Double(captured.pointSize.height),
                            pixelWidth: Int(captured.pixelSize.width.rounded()),
                            pixelHeight: Int(captured.pixelSize.height.rounded()),
                            scale: Double(captured.scale),
                            captureExtent: policy.captureExtent.rawValue,
                        ))
                    }
                }
            }

            try Task.checkCancellation()
            let manifest = try makeManifest(
                build: build,
                profiles: profiles,
                screens: preparedScreens,
                routes: preparedRoutes,
                layout: layout,
                pathsByVariant: pathsByVariant,
                images: images,
            )
            try write(manifest: manifest, to: directory)
            let actualImageCount = try pngCount(in: imagesDirectory)
            guard actualImageCount == images.count else {
                throw FlyoverExportError.assetCountMismatch(
                    expected: images.count,
                    actual: actualImageCount,
                )
            }

            return try FlyoverExportSummary(
                screenCount: preparedScreens.count,
                stateCount: preparedScreens.reduce(0) { $0 + $1.screen.variants.count },
                profileCount: profiles.count,
                imageCount: images.count,
                outputByteCount: directoryByteCount(directory),
                outputDirectory: directory,
            )
        }

        private func prepareScreens() throws -> [PreparedScreen] {
            guard catalog.isValid else {
                throw FlyoverExportError.invalidCatalog(issueCount: catalog.validationIssues.count)
            }
            guard applicationID.isEmpty == false else {
                throw FlyoverExportError.emptyApplicationIdentifier
            }

            var seenScreenIDs: Set<String> = []
            var prepared: [PreparedScreen] = []
            var screenOrdinal = 0
            for (groupIndex, group) in catalog.groups.enumerated() {
                for (screenIndex, screen) in group.screens.enumerated() {
                    screenOrdinal += 1
                    let stableID = screenIdentifier(screen.id)
                    guard stableID.isEmpty == false else {
                        throw FlyoverExportError.emptyScreenIdentifier(
                            screenTitle: screen.title,
                        )
                    }
                    guard seenScreenIDs.insert(stableID).inserted else {
                        throw FlyoverExportError.duplicateScreenIdentifier(stableID)
                    }
                    var seenVariants: Set<String> = []
                    for variant in screen.variants {
                        guard variant.id.rawValue.isEmpty == false else {
                            throw FlyoverExportError.emptyVariantIdentifier(screen: stableID)
                        }
                        guard seenVariants.insert(variant.id.rawValue).inserted else {
                            throw FlyoverExportError.duplicateVariantIdentifier(
                                screen: stableID,
                                variant: variant.id.rawValue,
                            )
                        }
                    }
                    prepared.append(PreparedScreen(
                        groupID: group.id.rawValue,
                        groupTitle: group.title,
                        groupOrder: groupIndex,
                        screenOrder: screenIndex,
                        screenOrdinal: screenOrdinal,
                        stableID: stableID,
                        screen: screen,
                    ))
                }
            }
            return prepared
        }

        private func validatePolicies(in screens: [PreparedScreen]) throws {
            for prepared in screens {
                for variant in prepared.screen.variants {
                    _ = try resolvedPolicy(variant, screen: prepared.stableID)
                }
            }
        }

        private func resolvedPolicy(
            _ variant: FlyoverVariant,
            screen: String,
        ) throws -> FlyoverExportPolicy {
            switch variant.exportPolicyResolution {
                case let .policy(policy):
                    return policy
                case let .mixed(extents):
                    throw FlyoverExportError.mixedSizingPolicy(
                        screen: screen,
                        variant: variant.id.rawValue,
                        extents: extents.map(\.rawValue),
                    )
            }
        }

        private func prepareRoutes(
            screens: [PreparedScreen],
            layout: FlyoverLayoutResult<ScreenID>,
        ) throws -> [PreparedRoute] {
            let stableIDs = stableIDMap(for: screens)
            return try catalog.transitions.enumerated().map { index, transition in
                guard let sourceID = stableIDs[transition.source],
                      let destinationID = stableIDs[transition.destination],
                      let sourceFrame = layout.screenFrames[transition.source],
                      let destinationFrame = layout.screenFrames[transition.destination]
                else {
                    throw FlyoverExportError.missingManifestGeometry(
                        kind: "route",
                        identifier: String(format: "route-%04d", index + 1),
                    )
                }
                let geometry = FlyoverConnectorGeometry(
                    source: sourceFrame,
                    destination: destinationFrame,
                    style: FlyoverStylesheet.default.connector,
                )
                return PreparedRoute(
                    id: String(format: "route-%04d", index + 1),
                    sourceID: sourceID,
                    destinationID: destinationID,
                    kind: transition.kind.rawValue,
                    label: transition.label,
                    geometry: geometry,
                )
            }
        }

        private func makeManifest(
            build: FlyoverExportBuild,
            profiles: [FlyoverCaptureProfile],
            screens: [PreparedScreen],
            routes: [PreparedRoute],
            layout: FlyoverLayoutResult<ScreenID>,
            pathsByVariant: [VariantKey: [String: String]],
            images: [FlyoverWebManifest.Image],
        ) throws -> FlyoverWebManifest {
            let stableIDs = stableIDMap(for: screens)
            let groups = try catalog.groups.enumerated().map { index, group in
                guard let rootScreenID = stableIDs[group.root] else {
                    throw FlyoverExportError.missingManifestGeometry(
                        kind: "group root",
                        identifier: group.id.rawValue,
                    )
                }
                let screenIDs = try group.screens.map { screen in
                    guard let stableID = stableIDs[screen.id] else {
                        throw FlyoverExportError.missingManifestGeometry(
                            kind: "screen identity",
                            identifier: screen.title,
                        )
                    }
                    return stableID
                }
                return FlyoverWebManifest.Group(
                    id: group.id.rawValue,
                    title: group.title,
                    order: index,
                    rootScreenID: rootScreenID,
                    screenIDs: screenIDs,
                )
            }
            let manifestRoutes = routes.map { route in
                FlyoverWebManifest.Route(
                    id: route.id,
                    sourceScreenID: route.sourceID,
                    destinationScreenID: route.destinationID,
                    kind: route.kind,
                    label: route.label,
                    geometry: route.geometry.manifestValue,
                )
            }
            let manifestScreens = try screens.map { prepared in
                guard let screenFrame = layout.screenFrames[prepared.screen.id] else {
                    throw FlyoverExportError.missingManifestGeometry(
                        kind: "screen frame",
                        identifier: prepared.stableID,
                    )
                }
                let variants = try prepared.screen.variants.map { variant in
                    let policy = try resolvedPolicy(variant, screen: prepared.stableID)
                    let key = VariantKey(
                        screenID: prepared.stableID,
                        variantID: variant.id.rawValue,
                    )
                    return FlyoverWebManifest.Variant(
                        id: variant.id.rawValue,
                        title: variant.title,
                        captureExtent: policy.captureExtent.rawValue,
                        imagesByProfile: pathsByVariant[key] ?? [:],
                    )
                }
                return FlyoverWebManifest.Screen(
                    id: prepared.stableID,
                    title: prepared.screen.title,
                    groupID: prepared.groupID,
                    groupOrder: prepared.groupOrder,
                    screenOrder: prepared.screenOrder,
                    viewport: prepared.screen.viewport.manifestValue,
                    navigationContainer: prepared.screen.navigationContainer.manifestValue,
                    frame: FlyoverWebManifest.Rect(screenFrame),
                    variants: variants,
                    incomingRouteIDs: routes
                        .filter { $0.destinationID == prepared.stableID }
                        .map(\.id),
                    outgoingRouteIDs: routes
                        .filter { $0.sourceID == prepared.stableID }
                        .map(\.id),
                )
            }
            let groupFrames = try catalog.groups
                .map { group -> FlyoverWebManifest.IdentifiedFrame in
                    guard let frame = layout.groupFrames[group.id] else {
                        throw FlyoverExportError.missingManifestGeometry(
                            kind: "group frame",
                            identifier: group.id.rawValue,
                        )
                    }
                    return FlyoverWebManifest.IdentifiedFrame(
                        id: group.id.rawValue,
                        frame: FlyoverWebManifest.Rect(frame),
                    )
                }
            let screenFrames = try screens
                .map { prepared -> FlyoverWebManifest.IdentifiedFrame in
                    guard let frame = layout.screenFrames[prepared.screen.id] else {
                        throw FlyoverExportError.missingManifestGeometry(
                            kind: "screen frame",
                            identifier: prepared.stableID,
                        )
                    }
                    return FlyoverWebManifest.IdentifiedFrame(
                        id: prepared.stableID,
                        frame: FlyoverWebManifest.Rect(frame),
                    )
                }
            let depthBands = layout.depthBands.map { band in
                let kind: String
                let depth: Int?
                switch band.kind {
                    case let .route(value):
                        kind = "route"
                        depth = value
                    case .unlinked:
                        kind = "unlinked"
                        depth = nil
                }
                return FlyoverWebManifest.DepthBandFrame(
                    groupID: band.id.group.rawValue,
                    kind: kind,
                    depth: depth,
                    frame: FlyoverWebManifest.Rect(band.frame),
                )
            }
            return FlyoverWebManifest(
                schemaVersion: 1,
                application: FlyoverWebManifest.Application(id: applicationID, title: title),
                build: build,
                profiles: profiles.map(\.manifestValue),
                canvas: FlyoverWebManifest.Canvas(
                    size: FlyoverWebManifest.Size(layout.canvasSize),
                    initialFitSize: FlyoverWebManifest.Size(layout.initialCanvasSize),
                    groupFrames: groupFrames,
                    depthBandFrames: depthBands,
                    screenFrames: screenFrames,
                    connectors: routes.map {
                        FlyoverWebManifest.Connector(
                            routeID: $0.id,
                            geometry: $0.geometry.manifestValue,
                        )
                    },
                ),
                groups: groups,
                screens: manifestScreens,
                routes: manifestRoutes,
                images: images,
            )
        }

        private func stableIDMap(for screens: [PreparedScreen]) -> [ScreenID: String] {
            screens.reduce(into: [:]) { result, prepared in
                result[prepared.screen.id] = prepared.stableID
            }
        }

        private func write(manifest: FlyoverWebManifest, to directory: URL) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data: Data
            do {
                data = try encoder.encode(manifest)
            } catch {
                throw FlyoverExportError.outputWriteFailed(
                    path: directory.appending(path: "manifest.json").path,
                    reason: error.localizedDescription,
                )
            }
            do {
                try data.write(
                    to: directory.appending(path: "manifest.json"),
                    options: .atomic,
                )
                var script = Data("window.FLYOVER_MANIFEST = ".utf8)
                script.append(data)
                script.append(Data(";\n".utf8))
                try script.write(
                    to: directory.appending(path: "manifest.js"),
                    options: .atomic,
                )
            } catch {
                throw FlyoverExportError.outputWriteFailed(
                    path: directory.path,
                    reason: error.localizedDescription,
                )
            }
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

        private func directoryByteCount(_ directory: URL) throws -> Int {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey],
            ) else {
                return 0
            }
            return try enumerator.compactMap { value -> Int? in
                guard let url = value as? URL else { return nil }
                return try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            }.reduce(0, +)
        }

        private struct PreparedScreen {
            let groupID: String
            let groupTitle: String
            let groupOrder: Int
            let screenOrder: Int
            let screenOrdinal: Int
            let stableID: String
            let screen: FlyoverScreen<ScreenID>
        }

        private struct PreparedRoute {
            let id: String
            let sourceID: String
            let destinationID: String
            let kind: String
            let label: String?
            let geometry: FlyoverConnectorGeometry
        }

        private struct VariantKey: Hashable {
            let screenID: String
            let variantID: String
        }
    }

    extension FlyoverCaptureProfile {
        fileprivate var manifestValue: FlyoverWebManifest.Profile {
            FlyoverWebManifest.Profile(
                id: rawValue,
                title: title,
                device: deviceName,
                orientation: orientationName,
                colorScheme: colorSchemeName,
                dynamicType: dynamicTypeName,
                contrast: contrastName,
                layoutDirection: layoutDirectionName,
                legibilityWeight: legibilityWeightName,
                snapshotType: snapshotTypeName,
            )
        }
    }

    extension FlyoverViewport {
        fileprivate var manifestValue: FlyoverWebManifest.Viewport {
            switch self {
                case .device:
                    FlyoverWebManifest.Viewport(kind: "device", fixedSize: nil)
                case let .fixed(size):
                    FlyoverWebManifest.Viewport(
                        kind: "fixed",
                        fixedSize: FlyoverWebManifest.Size(size),
                    )
            }
        }
    }

    extension FlyoverNavigationContainer {
        fileprivate var manifestValue: String {
            switch self {
                case .stack: "stack"
                case .none: "none"
            }
        }
    }

    extension FlyoverConnectorGeometry {
        fileprivate var manifestValue: FlyoverWebManifest.ConnectorGeometry {
            FlyoverWebManifest.ConnectorGeometry(
                start: FlyoverWebManifest.Point(start),
                end: FlyoverWebManifest.Point(end),
                firstControl: FlyoverWebManifest.Point(firstControl),
                secondControl: FlyoverWebManifest.Point(secondControl),
                firstArrowPoint: FlyoverWebManifest.Point(firstArrowPoint),
                secondArrowPoint: FlyoverWebManifest.Point(secondArrowPoint),
            )
        }
    }
#endif
