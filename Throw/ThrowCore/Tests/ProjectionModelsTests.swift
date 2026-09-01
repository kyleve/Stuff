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
        )
        let first = try semanticMark(id: id, label: "FIRST")
        let replacement = try semanticMark(id: id, label: "REPLACEMENT")
        let semanticLayer = ProjectionLayerFrame<FlightsLayerKind>(
            observedAt: ThrowCoreFixture.date,
            marks: [first, replacement],
        )

        let firstProjected = try projectedFlightMark(id: id, x: 0.2)
        let replacementProjected = try projectedFlightMark(id: id, x: 0.8)
        let projectedLayer = ProjectedLayerFrame<FlightsLayerKind>(
            marks: [firstProjected, replacementProjected],
        )

        #expect(semanticLayer.marks.count == 1)
        #expect(semanticLayer.marks.first?.label?.primary == "REPLACEMENT")
        #expect(projectedLayer.marks.count == 1)
        #expect(projectedLayer.marks.first?.point.x == 0.8)
    }

    @Test func airportElementDerivesIdentityFromItsGlyphDescriptor() {
        let airportID = AirportID(rawValue: 42)
        let descriptor = AirportGlyphDescriptor(
            airportID: airportID,
            code: nil,
            runwayBearing: nil,
            certainty: .confirmed,
        )

        let element = FlightsMarkElement.airport(descriptor)

        #expect(element.id == .airport(airportID))
        #expect(element.glyph == .airport(descriptor))
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
        let geographyLines = ProjectedLineCollection<GeographyLineKind>.testing(
            id: ProjectionLineRevisionID.testing(rawValue: 1),
            segments: [],
        )
        let networkLines = ProjectedLineCollection<TransitNetworkLineStyle>.testing(
            id: ProjectionLineRevisionID.testing(rawValue: 2),
            segments: [],
        )
        let geography = ProjectedLayerFrame<GeographyLayerKind>.testing(lines: geographyLines)
        let network = ProjectedLayerFrame<TransitNetworkLayerKind>.testing(lines: networkLines)
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

    @Test func projectedExperienceRetainsMarksInTheirTypedLayers() throws {
        let aircraftID = try #require(AircraftID(kind: .icao, rawValue: "a"))
        let aircraft = try ProjectedMark(
            element: FlightsMarkElement.aircraft(id: aircraftID, glyph: .unknownAirborne),
            point: ProjectionPoint(x: 0.5, y: 0.5),
            range: NauticalMiles(value: 1),
            label: nil,
            secondaryProminence: 0,
            orientationDegrees: nil,
            opacity: 1,
            labelOpacity: 1,
            altitudeIsApproximate: false,
        )
        let starID = try #require(StarID(rawValue: "s"))
        let star = try ProjectedMark(
            element: StarMarkElement(id: starID),
            point: ProjectionPoint(x: 0.5, y: 0.5),
            range: nil,
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
        guard case let .airAndSpace(.trueSky(projected)) = frame else {
            Issue.record("The projected Air & Space frame changed experience cases.")
            return
        }
        #expect(projected.flights?.marks == [aircraft])
        #expect(projected.stars?.marks == [star])
    }

    @Test func lineLayersRetainTheirConcreteStyleFamilies() throws {
        let bounds = try GeographicBounds(
            southLatitude: 0,
            westLongitude: 0,
            northLatitude: 1,
            eastLongitude: 1,
        )
        let coordinates = try [
            GeoCoordinate(latitude: 0, longitude: 0),
            GeoCoordinate(latitude: 1, longitude: 1),
        ]
        let geography = try GeographicPolyline(
            kind: .coastline,
            detailLevel: .wide,
            bounds: bounds,
            coordinates: coordinates,
        )
        let transit = try ProjectionPolyline<TransitNetworkLineStyle>(
            style: .route,
            detailLevel: .wide,
            bounds: bounds,
            coordinates: coordinates,
        )

        #expect(geography.style == .coastline)
        #expect(transit.style == .route)
    }

    @Test func projectedExperienceFixesTransitLayersAndMode() throws {
        let vehicleID = try #require(TransitVehicleID(rawValue: "vehicle"))
        let mark = try ProjectedMark(
            element: TransitVehicleMarkElement(id: vehicleID),
            point: ProjectionPoint(x: 0.5, y: 0.5),
            range: NauticalMiles(value: 1),
            label: nil,
            secondaryProminence: 0,
            orientationDegrees: nil,
            opacity: 1,
            labelOpacity: 1,
            altitudeIsApproximate: false,
        )
        let lines = ProjectedLineCollection<TransitNetworkLineStyle>.testing(
            id: ProjectionLineRevisionID.testing(rawValue: 7),
            segments: [ProjectedLineSegment(
                style: .route,
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
        let aircraftID = try #require(AircraftID(kind: .icao, rawValue: markIDSentinel))
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
            element: FlightsMarkElement.aircraft(
                id: aircraftID,
                glyph: .unknownAirborne,
            ),
            anchor: anchor,
            label: label,
            prominence: .primary,
            velocity: nil,
            freshness: MarkFreshness(
                positionObservedAt: ThrowCoreFixture.date,
                fetchedAt: ThrowCoreFixture.date,
                availability: .current,
            ),
        )
        let layerFrame = ProjectionLayerFrame<FlightsLayerKind>(
            observedAt: ThrowCoreFixture.date,
            marks: [mark],
        )
        let projectedMark = try ProjectedMark(
            element: FlightsMarkElement.aircraft(
                id: aircraftID,
                glyph: .unknownAirborne,
            ),
            point: ProjectionPoint(x: 0.4, y: 0.6),
            range: NauticalMiles(value: 5),
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

    private func semanticMark(
        id: AircraftID,
        label: String,
    ) throws -> ProjectionMark<FlightsMarkElement> {
        try ProjectionMark(
            element: .aircraft(id: id, glyph: .unknownAirborne),
            anchor: .geodetic(GeodeticAnchor(
                coordinate: GeoCoordinate(latitude: 37, longitude: -122),
                altitude: .available(Altitude(feet: 10000), quality: .geometric),
            )),
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

    private func projectedFlightMark(
        id: AircraftID,
        x: Double = 0.5,
    ) throws -> ProjectedMark<FlightsMarkElement> {
        try ProjectedMark(
            element: .aircraft(id: id, glyph: .unknownAirborne),
            point: ProjectionPoint(x: x, y: 0.5),
            range: NauticalMiles(value: 1),
            label: nil,
            secondaryProminence: 0,
            orientationDegrees: nil,
            opacity: 1,
            labelOpacity: 1,
            altitudeIsApproximate: false,
        )
    }
}
