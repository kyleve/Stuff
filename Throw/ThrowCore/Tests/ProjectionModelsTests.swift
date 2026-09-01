import Foundation
import Testing
@_spi(Testing) @testable import ThrowCore

struct ProjectionModelsTests {
    @Test func geodeticAltitudeCarriesQualityOnlyWithAValue() throws {
        let unavailable = GeodeticAltitude.unavailable
        let available = try GeodeticAltitude.available(
            Altitude(feet: 12000),
            quality: .barometricApproximation,
        )

        #expect(unavailable.value == nil)
        #expect(unavailable.quality == nil)
        #expect(available.value?.feet == 12000)
        #expect(available.quality == .barometricApproximation)
    }

    @Test func calibrationRejectsInsetAboveTwentyPercent() throws {
        #expect(throws: ThrowValidationError.self) {
            try ProjectionCalibration(
                screenTopBearing: Bearing(degrees: 0),
                rotation: .degrees0,
                flipHorizontal: false,
                flipVertical: false,
                safeInsetFraction: 0.21,
                verifiedOnExternalDisplay: false,
            )
        }
    }

    @Test func calibrationBearingReplacementPreservesTheValidatedCalibration() throws {
        let calibration = try ProjectionCalibration(
            screenTopBearing: Bearing(degrees: 15),
            rotation: .degrees270,
            flipHorizontal: true,
            flipVertical: false,
            safeInsetFraction: 0.12,
            verifiedOnExternalDisplay: true,
        )

        let replacement = try calibration.replacingScreenTopBearing(
            Bearing(degrees: 725),
        )

        #expect(replacement.screenTopBearing.degrees == 5)
        #expect(replacement.rotation == calibration.rotation)
        #expect(replacement.flipHorizontal == calibration.flipHorizontal)
        #expect(replacement.flipVertical == calibration.flipVertical)
        #expect(replacement.safeInsetFraction == calibration.safeInsetFraction)
        #expect(
            replacement.verifiedOnExternalDisplay == calibration.verifiedOnExternalDisplay,
        )

        let edited = try replacement
            .replacingRotation(.degrees90)
            .replacingFlipHorizontal(false)
            .replacingFlipVertical(true)
            .replacingSafeInsetFraction(0.08)
            .replacingVerifiedOnExternalDisplay(false)
        #expect(edited.screenTopBearing == replacement.screenTopBearing)
        #expect(edited.rotation == .degrees90)
        #expect(edited.flipHorizontal == false)
        #expect(edited.flipVertical)
        #expect(edited.safeInsetFraction == 0.08)
        #expect(edited.verifiedOnExternalDisplay == false)
        #expect(throws: ThrowValidationError.self) {
            try edited.replacingSafeInsetFraction(0.21)
        }
    }

    @Test func markIdentityIncludesLayerAndNamespace() throws {
        let aircraft = try #require(
            AircraftID(kind: .icao, rawValue: "same"),
        ).layerMarkID
        let satellite = try LayerMarkID.satellite(#require(SatelliteID(rawValue: "same")))
        let nonICAOAircraft = try #require(
            AircraftID(kind: .providerMarkedNonICAO, rawValue: "same"),
        ).layerMarkID
        #expect(aircraft != satellite)
        #expect(aircraft != nonICAOAircraft)
        #expect(aircraft.rawValue != nonICAOAircraft.rawValue)
    }

    @Test func semanticAndProjectedLayersRetainOneValuePerMarkIdentity() throws {
        let id = try #require(
            AircraftID(kind: .icao, rawValue: "duplicate"),
        ).layerMarkID
        let first = try semanticMark(id: id, label: "FIRST")
        let replacement = try semanticMark(id: id, label: "REPLACEMENT")
        let semanticLayer = LayerFrame(
            layerID: .flights,
            observedAt: ThrowCoreFixture.date,
            content: .marks([first, replacement]),
        )

        let firstProjected = try projectedMark(
            layerID: .flights,
            rawID: "duplicate",
            x: 0.2,
        )
        let replacementProjected = try projectedMark(
            layerID: .flights,
            rawID: "duplicate",
            x: 0.8,
        )
        let projectedLayer = ProjectedLayerFrame<FlightsLayerKind>(
            marks: [firstProjected, replacementProjected],
        )

        #expect(semanticLayer.marks.count == 1)
        #expect(semanticLayer.marks.first?.label?.primary == "REPLACEMENT")
        #expect(projectedLayer.marks.count == 1)
        #expect(projectedLayer.marks.first?.point.x == 0.8)
    }

    @Test func experienceFramesExposeOnlyTheirTypedLayerMembership() {
        let flights = ProjectionLayerFrame<FlightsLayerKind>(
            observedAt: ThrowCoreFixture.date,
            marks: [],
        )
        let network = ProjectionLayerFrame<TransitNetworkLayerKind>(
            observedAt: ThrowCoreFixture.date,
            lines: [],
        )

        let airAndSpace = ProjectionExperienceFrame.airAndSpace(
            AirAndSpaceExperienceFrame(
                geography: nil,
                flights: flights,
                stars: nil,
                satellites: nil,
            ),
        )
        let transit = ProjectionExperienceFrame.transit(
            TransitExperienceFrame(
                geography: nil,
                network: network,
                vehicles: nil,
            ),
        )

        guard case let .airAndSpace(airAndSpaceFrame) = airAndSpace,
              case let .transit(transitFrame) = transit
        else {
            Issue.record("The experience cases changed unexpectedly.")
            return
        }
        #expect(airAndSpaceFrame.flights?.layerID == .flights)
        #expect(transitFrame.network?.layerID == .transitNetwork)
    }

    @Test func experienceProjectionInputsEncodeSupportedModes() throws {
        let mapViewport = try MapViewport(radius: NauticalMiles(value: 50))
        let skyViewport = try SkyViewport(minimumElevation: ElevationAngle(degrees: 10))
        let airMap = ProjectionExperienceInput.airAndSpace(AirAndSpaceProjectionInput(
            frame: .empty,
            viewport: .map(viewport: mapViewport, geography: .visible),
        ))
        let airSky = ProjectionExperienceInput.airAndSpace(AirAndSpaceProjectionInput(
            frame: .empty,
            viewport: .trueSky(viewport: skyViewport),
        ))
        let transit = ProjectionExperienceInput.transit(TransitProjectionInput(
            frame: .empty,
            viewport: mapViewport,
            geography: .visible,
        ))

        #expect(airMap.viewport == .map(mapViewport))
        #expect(airMap.requestsGeography)
        #expect(airSky.viewport == .trueSky(skyViewport))
        #expect(airSky.requestsGeography == false)
        #expect(transit.viewport == .map(mapViewport))
        #expect(transit.requestsGeography)
    }

    @Test func preparedInputsDiscardStaticLayersThatTheirSemanticInputCannotUse() throws {
        let mapViewport = try MapViewport(radius: NauticalMiles(value: 50))
        let skyViewport = try SkyViewport(minimumElevation: ElevationAngle(degrees: 10))
        let lines = ProjectedLineCollection.testing(
            id: ProjectionLineRevisionID.testing(rawValue: 1),
            segments: [],
        )
        let geography = ProjectedLayerFrame<GeographyLayerKind>.testing(lines: lines)
        let network = ProjectedLayerFrame<TransitNetworkLayerKind>.testing(lines: lines)
        var projectedMissingNetwork = false
        let sky = PreparedAirAndSpaceProjectionInput(
            input: AirAndSpaceProjectionInput(
                frame: .empty,
                viewport: .trueSky(viewport: skyViewport),
            ),
            geography: geography,
        )
        let transit = PreparedTransitProjectionInput(
            input: TransitProjectionInput(
                frame: .empty,
                viewport: mapViewport,
                geography: .hidden,
            ),
            geography: geography,
            projectNetwork: { _ in
                projectedMissingNetwork = true
                return network
            },
        )

        #expect(sky.geography == nil)
        #expect(transit.geography == nil)
        #expect(transit.network == nil)
        #expect(projectedMissingNetwork == false)
    }

    @Test func preparedTransitPairsARequiredNetworkWithItsProjection() throws {
        let mapViewport = try MapViewport(radius: NauticalMiles(value: 50))
        let source = ProjectionLayerFrame<TransitNetworkLayerKind>(
            observedAt: ThrowCoreFixture.date,
            lines: [],
        )
        let projected = ProjectedLayerFrame<TransitNetworkLayerKind>.testing(
            lines: ProjectedLineCollection.testing(
                id: ProjectionLineRevisionID.testing(rawValue: 1),
                segments: [],
            ),
        )
        var projectedSource: ProjectionLayerFrame<TransitNetworkLayerKind>?

        let prepared = PreparedTransitProjectionInput(
            input: TransitProjectionInput(
                frame: TransitExperienceFrame(
                    geography: nil,
                    network: source,
                    vehicles: nil,
                ),
                viewport: mapViewport,
                geography: .hidden,
            ),
            geography: nil,
        ) { source in
            projectedSource = source
            return projected
        }

        #expect(projectedSource == source)
        #expect(prepared.network?.sourceRevision == source.observedAt)
        #expect(prepared.network?.frame == projected)
    }

    @Test func projectedExperienceCollectsMarksFromItsTypedLayers() throws {
        let aircraft = try ProjectedMark(
            id: #require(AircraftID(kind: .icao, rawValue: "a")).layerMarkID,
            point: ProjectionPoint(x: 0.5, y: 0.5),
            range: NauticalMiles(value: 1),
            glyph: .aircraft(.unknownAirborne),
            label: nil,
            secondaryProminence: 0,
            orientationDegrees: nil,
            opacity: 1,
            labelOpacity: 1,
            altitudeIsApproximate: false,
        )
        let star = try ProjectedMark(
            id: .star(#require(StarID(rawValue: "s"))),
            point: ProjectionPoint(x: 0.5, y: 0.5),
            range: nil,
            glyph: .star,
            label: nil,
            secondaryProminence: 0,
            orientationDegrees: nil,
            opacity: 1,
            labelOpacity: 1,
            altitudeIsApproximate: false,
        )
        let frame = ProjectedExperienceFrame.airAndSpace(.trueSky(
            AirAndSpaceTrueSkyProjectedFrame(
                generatedAt: .now,
                flights: ProjectedLayerFrame(marks: [aircraft]),
                stars: ProjectedLayerFrame(marks: [star]),
                satellites: nil,
            ),
        ))
        #expect(frame.marks == [aircraft, star])
    }

    @Test func lineStyleIdentitySupportsGeographyAndFutureNetworks() {
        let coastline = ProjectionLineStyleID(geographyKind: .coastline)

        #expect(coastline.geographyKind == .coastline)
        #expect(ProjectionLineStyleID.transitRoute.geographyKind == nil)
        #expect(coastline != .transitRoute)
    }

    @Test func projectedExperienceFixesTransitLayersAndMode() throws {
        let mark = try projectedMark(layerID: .transitVehicles, rawID: "vehicle")
        let lines = ProjectedLineCollection.testing(
            id: ProjectionLineRevisionID.testing(rawValue: 7),
            segments: [ProjectedLineSegment(
                styleID: .transitRoute,
                start: ProjectionPoint(x: 0.1, y: 0.2),
                end: ProjectionPoint(x: 0.8, y: 0.9),
                startsNewSubpath: true,
            )],
        )
        let frame = ProjectedExperienceFrame.transit(TransitProjectedFrame(
            generatedAt: ThrowCoreFixture.date,
            geography: nil,
            network: .testing(lines: lines),
            vehicles: ProjectedLayerFrame(marks: [mark]),
        ))

        #expect(frame.experienceID == .transit)
        #expect(frame.mode == .map)
        guard case let .transit(transit) = frame else {
            Issue.record("The projected Transit frame changed experience cases.")
            return
        }
        #expect(transit.network?.lines == lines)
        #expect(transit.vehicles?.marks == [mark])
    }

    @Test func frameDescriptionsRedactMarksLabelsIdentitiesAndCoordinates() throws {
        let markIDSentinel = "mark-id-do-not-leak"
        let labelSentinel = "LABEL-DO-NOT-LEAK"
        let coordinateSentinel = "33.123456"
        let markID = try #require(
            AircraftID(kind: .icao, rawValue: markIDSentinel),
        ).layerMarkID
        let geodeticAnchor = try GeodeticAnchor(
            coordinate: GeoCoordinate(latitude: 33.123456, longitude: -111.654321),
            altitude: .available(Altitude(feet: 12300), quality: .geometric),
        )
        let anchor = ProjectionAnchor.geodetic(geodeticAnchor)
        let label = ProjectionLabel(
            primary: labelSentinel,
            primaryRole: .headline,
            secondary: "12,300 ft",
        )
        let mark = ProjectionMark(
            id: markID,
            anchor: anchor,
            glyph: .aircraft(.unknownAirborne),
            label: label,
            prominence: .primary,
            velocity: nil,
            freshness: MarkFreshness(
                positionObservedAt: ThrowCoreFixture.date,
                fetchedAt: ThrowCoreFixture.date,
                availability: .current,
            ),
        )
        let layerFrame = LayerFrame(
            layerID: .flights,
            observedAt: ThrowCoreFixture.date,
            content: .marks([mark]),
        )
        let projectedMark = try ProjectedMark(
            id: markID,
            point: ProjectionPoint(x: 0.4, y: 0.6),
            range: NauticalMiles(value: 5),
            glyph: .aircraft(.unknownAirborne),
            label: label,
            secondaryProminence: 0,
            orientationDegrees: nil,
            opacity: 1,
            labelOpacity: 1,
            altitudeIsApproximate: false,
        )
        let renderings = [
            String(describing: markID),
            String(reflecting: markID),
            String(describing: geodeticAnchor),
            String(reflecting: geodeticAnchor),
            String(describing: anchor),
            String(reflecting: anchor),
            String(describing: label),
            String(reflecting: label),
            String(describing: mark),
            String(reflecting: mark),
            String(describing: layerFrame),
            String(reflecting: layerFrame),
            String(describing: projectedMark),
            String(reflecting: projectedMark),
        ]

        for rendering in renderings {
            #expect(rendering.contains(markIDSentinel) == false)
            #expect(rendering.contains(labelSentinel) == false)
            #expect(rendering.contains(coordinateSentinel) == false)
        }
    }

    private func semanticMark(id: LayerMarkID, label: String) throws -> ProjectionMark {
        try ProjectionMark(
            id: id,
            anchor: .geodetic(GeodeticAnchor(
                coordinate: GeoCoordinate(latitude: 37, longitude: -122),
                altitude: .available(Altitude(feet: 10000), quality: .geometric),
            )),
            glyph: .aircraft(.unknownAirborne),
            label: ProjectionLabel(
                primary: label,
                primaryRole: .headline,
                secondary: nil,
            ),
            prominence: .primary,
            velocity: nil,
            freshness: MarkFreshness(
                positionObservedAt: ThrowCoreFixture.date,
                fetchedAt: ThrowCoreFixture.date,
                availability: .current,
            ),
        )
    }

    private func projectedMark(
        layerID: LayerID,
        rawID: String,
        x: Double = 0.5,
    ) throws -> ProjectedMark {
        let id: LayerMarkID = switch layerID {
            case .transitVehicles:
                try .transitVehicle(#require(TransitVehicleID(rawValue: rawID)))
            case .flights:
                try #require(AircraftID(kind: .icao, rawValue: rawID)).layerMarkID
            case .geography, .stars, .satellites, .transitNetwork:
                throw ThrowValidationError.invalidPreferencePayload
        }
        return try ProjectedMark(
            id: id,
            point: ProjectionPoint(x: x, y: 0.5),
            range: NauticalMiles(value: 1),
            glyph: .aircraft(.unknownAirborne),
            label: nil,
            secondaryProminence: 0,
            orientationDegrees: nil,
            opacity: 1,
            labelOpacity: 1,
            altitudeIsApproximate: false,
        )
    }
}
