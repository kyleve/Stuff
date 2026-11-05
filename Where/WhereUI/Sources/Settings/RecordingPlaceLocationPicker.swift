import MapKit
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// Keeps map interaction and coordinate entry in one explicit, unsaved selection flow.
struct RecordingPlaceLocationPicker: View {
    @Bindable var model: RecordingPlaceLocationModel
    let use: (Coordinate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RecordingPlaceMap(model: model)
                    Text(String(localized: .recordingPlaceLocationDetail))
                }
                Section {
                    VStack(alignment: .leading) {
                        Text(String(localized: .recordingPlaceLatitude)).font(.caption)
                            .foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField(
                            String(localized: .recordingPlaceLatitude),
                            value: $model.latitude,
                            format: .number,
                        )
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityLabel(String(localized: .recordingPlaceLatitude))
                        .accessibilityIdentifier("where_recording_place_latitude")
                    }
                    VStack(alignment: .leading) {
                        Text(String(localized: .recordingPlaceLongitude)).font(.caption)
                            .foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField(
                            String(localized: .recordingPlaceLongitude),
                            value: $model.longitude,
                            format: .number,
                        )
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityLabel(String(localized: .recordingPlaceLongitude))
                        .accessibilityIdentifier("where_recording_place_longitude")
                    }
                    if let coordinate = model.coordinate {
                        Text(WhereFormat.auditCoordinate(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude,
                        ))
                        Button(String(localized: .recordingPlaceLocationUse)) {
                            use(coordinate)
                            dismiss()
                        }
                        .accessibilityIdentifier("where_recording_place_use_location")
                    } else {
                        Text(String(localized: .recordingPlaceCoordinateInvalid))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(String(localized: .recordingPlaceLocation))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .commonCancel)) { dismiss() }
                }
            }
        }
    }
}

/// Shared point-selection map. Remote tiles use a deterministic substrate during capture;
/// the explicit selection and map height stay the same. Live gestures are tested separately.
private struct RecordingPlaceMap: View {
    let model: RecordingPlaceLocationModel
    @Environment(\.stylesheet) private var stylesheet
    /// Capture infrastructure: MapKit's remote tiles have no deterministic settle state.
    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot

    var body: some View {
        Group {
            if isCapturingSnapshot {
                ZStack {
                    Color(.secondarySystemBackground)
                    if model.coordinate != nil {
                        Image(systemSymbol: .mappinCircleFill)
                            .font(stylesheet.recordingPlaceMap.capturePinFont)
                            .foregroundStyle(.tint)
                    }
                }
            } else {
                MapReader { proxy in
                    Map(initialPosition: initialPosition) {
                        if let coordinate = model.coordinate {
                            Marker(
                                String(localized: .recordingPlaceLocation),
                                coordinate: coordinate.clLocationCoordinate,
                            )
                        }
                    }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .onTapGesture { point in
                        if let coordinate = proxy.convert(point, from: .local) {
                            model.select(Coordinate(coordinate))
                        }
                    }
                }
            }
        }
        .frame(height: stylesheet.recordingPlaceMap.height)
        .accessibilityLabel(String(localized: .recordingPlaceLocation))
        .accessibilityIdentifier("where_recording_place_map")
    }

    private var initialPosition: MapCameraPosition {
        guard let coordinate = model.initialCoordinate else { return .automatic }
        return .region(MKCoordinateRegion(
            center: coordinate.clLocationCoordinate,
            latitudinalMeters: stylesheet.recordingPlaceMap.initialSpanMeters,
            longitudinalMeters: stylesheet.recordingPlaceMap.initialSpanMeters,
        ))
    }
}

#if DEBUG
    extension RecordingPlaceLocationPicker: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Selected",
                configurations: .fullContentPhoneLightDarkWithAX5AndAnnotations,
            ) {
                RecordingPlaceLocationPicker(
                    model: .init(coordinate: .init(latitude: 40.71, longitude: -74)),
                    use: { _ in },
                )
            }
            whereSnapshot(name: "Empty", configurations: [.init(device: .iPhoneFullContent)]) {
                RecordingPlaceLocationPicker(model: .init(coordinate: nil), use: { _ in })
            }
        }
    }

    #Preview { RecordingPlaceLocationPicker.snapshotPreviews }
    extension RecordingPlaceLocationPicker: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            RecordingPlaceLocationPicker.self,
            title: "Place location",
            navigationContainer: .none,
        )
    }
#endif
