import Foundation
import RegionKit
import WhereCore

/// A complete recorded GPS window with shifted dates, replacement IDs,
/// and rotated coordinates. Expected behavior is defined in the analyzer tests.
enum RecordedSparseFlightFixture {
    static let now = Date(timeIntervalSince1970: 1_578_001_800.0)
    static let samples: [LocationSample] = [
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000074")!,
            timestamp: Date(timeIntervalSince1970: 1_577_842_352.1889548),
            coordinate: Coordinate(latitude: 15.000000000000002, longitude: -29.999999999999996),
            horizontalAccuracy: 33.70587584638984,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 68.23993211769746,
                    accuracyMeters: 6.053806360193494,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            timestamp: Date(timeIntervalSince1970: 1_577_842_662.357819),
            coordinate: Coordinate(latitude: 15.00583453565946, longitude: -29.97319855126153),
            horizontalAccuracy: 1000.0,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 6.788533649679881,
                    accuracyMeters: 6.235022574172432,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000043")!,
            timestamp: Date(timeIntervalSince1970: 1_577_842_950.4945226),
            coordinate: Coordinate(latitude: 15.011880910280496, longitude: -29.968311502605797),
            horizontalAccuracy: 73.42170175212742,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000024")!,
            timestamp: Date(timeIntervalSince1970: 1_577_842_962.40722),
            coordinate: Coordinate(latitude: 15.011634987902607, longitude: -29.96861392169366),
            horizontalAccuracy: 18.041474056985933,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(meters: 39.6835253900041, accuracyMeters: 3.0),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            timestamp: Date(timeIntervalSince1970: 1_577_844_585.4754128),
            coordinate: Coordinate(latitude: 15.011728044988066, longitude: -29.968097751056757),
            horizontalAccuracy: 20.0,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(meters: 149.05504268476918, accuracyMeters: 30.0),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000017")!,
            timestamp: Date(timeIntervalSince1970: 1_577_844_585.4754128),
            coordinate: Coordinate(latitude: 15.011728044988066, longitude: -29.968097751056757),
            horizontalAccuracy: 20.0,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(meters: 149.05504268476918, accuracyMeters: 30.0),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            timestamp: Date(timeIntervalSince1970: 1_577_864_906.0004272),
            coordinate: Coordinate(latitude: 15.011752919018555, longitude: -29.96819220297112),
            horizontalAccuracy: 30.122834182384747,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000027")!,
            timestamp: Date(timeIntervalSince1970: 1_577_865_067.089412),
            coordinate: Coordinate(latitude: 15.007203278400718, longitude: -29.967567904838013),
            horizontalAccuracy: 8.000000436236272,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: LocationMotion
                    .Speed(
                        metersPerSecond: 13.180892411854952,
                        accuracyMetersPerSecond: 1.6045666536773175,
                    ),
                altitude: LocationMotion.Altitude(
                    meters: 9.87891736254096,
                    accuracyMeters: 6.007292449812261,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000065")!,
            timestamp: Date(timeIntervalSince1970: 1_577_865_367.820607),
            coordinate: Coordinate(latitude: 14.967972465416853, longitude: -29.97306013310606),
            horizontalAccuracy: 1000.0,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(meters: 26.434482320187428, accuracyMeters: 3.0),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000033")!,
            timestamp: Date(timeIntervalSince1970: 1_577_865_672.766768),
            coordinate: Coordinate(latitude: 14.893307196693858, longitude: -29.97107298262547),
            horizontalAccuracy: 84.6074553864506,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(meters: 16.61400014245305, accuracyMeters: 3.0),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000059")!,
            timestamp: Date(timeIntervalSince1970: 1_577_865_973.0869122),
            coordinate: Coordinate(latitude: 14.84080450858514, longitude: -29.963111682895498),
            horizontalAccuracy: 2.0168550006208856,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: LocationMotion
                    .Speed(
                        metersPerSecond: 7.503861100524013,
                        accuracyMetersPerSecond: 0.9433162234371579,
                    ),
                altitude: LocationMotion.Altitude(meters: 9.9359914297238, accuracyMeters: 3.0),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            timestamp: Date(timeIntervalSince1970: 1_577_866_527.199308),
            coordinate: Coordinate(latitude: 14.84141084767847, longitude: -29.961278271831198),
            horizontalAccuracy: 18.726415761601324,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000050")!,
            timestamp: Date(timeIntervalSince1970: 1_577_866_527.199308),
            coordinate: Coordinate(latitude: 14.840798938919757, longitude: -29.960496258497955),
            horizontalAccuracy: 79.0046906994093,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000056")!,
            timestamp: Date(timeIntervalSince1970: 1_577_873_129.20175),
            coordinate: Coordinate(latitude: 14.828361507504637, longitude: -29.961563832151885),
            horizontalAccuracy: 155.99802669832948,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: -18.11599985754694,
                    accuracyMeters: 5.207835909233763,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000064")!,
            timestamp: Date(timeIntervalSince1970: 1_577_873_382.080328),
            coordinate: Coordinate(latitude: 14.958608233170475, longitude: -29.799616657329054),
            horizontalAccuracy: 27.400679403751347,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: LocationMotion
                    .Speed(
                        metersPerSecond: 141.15945431116234,
                        accuracyMetersPerSecond: 1.869488358040168,
                    ),
                altitude: LocationMotion.Altitude(
                    meters: 2323.6848056083545,
                    accuracyMeters: 31.141836161711268,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000072")!,
            timestamp: Date(timeIntervalSince1970: 1_577_873_382.080328),
            coordinate: Coordinate(latitude: 14.958608233170475, longitude: -29.799616657329054),
            horizontalAccuracy: 27.400679403751347,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: LocationMotion
                    .Speed(
                        metersPerSecond: 141.15945431116234,
                        accuracyMetersPerSecond: 1.869488358040168,
                    ),
                altitude: LocationMotion.Altitude(
                    meters: 2323.6848056083545,
                    accuracyMeters: 31.141836161711268,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000040")!,
            timestamp: Date(timeIntervalSince1970: 1_577_873_382.080328),
            coordinate: Coordinate(latitude: 14.958608233170475, longitude: -29.799616657329054),
            horizontalAccuracy: 27.400679403751347,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: LocationMotion
                    .Speed(
                        metersPerSecond: 141.15945431116234,
                        accuracyMetersPerSecond: 1.869488358040168,
                    ),
                altitude: LocationMotion.Altitude(
                    meters: 2323.6848056083545,
                    accuracyMeters: 31.141836161711268,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000035")!,
            timestamp: Date(timeIntervalSince1970: 1_577_873_382.080328),
            coordinate: Coordinate(latitude: 14.958608233170475, longitude: -29.799616657329054),
            horizontalAccuracy: 27.400679403751347,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: LocationMotion
                    .Speed(
                        metersPerSecond: 141.15945431116234,
                        accuracyMetersPerSecond: 1.869488358040168,
                    ),
                altitude: LocationMotion.Altitude(
                    meters: 2323.6848056083545,
                    accuracyMeters: 31.141836161711268,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000019")!,
            timestamp: Date(timeIntervalSince1970: 1_577_873_382.080328),
            coordinate: Coordinate(latitude: 14.958608233170475, longitude: -29.799616657329054),
            horizontalAccuracy: 27.400679403751347,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: LocationMotion
                    .Speed(
                        metersPerSecond: 141.15945431116234,
                        accuracyMetersPerSecond: 1.869488358040168,
                    ),
                altitude: LocationMotion.Altitude(
                    meters: 2323.6848056083545,
                    accuracyMeters: 31.141836161711268,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000070")!,
            timestamp: Date(timeIntervalSince1970: 1_577_873_382.080328),
            coordinate: Coordinate(latitude: 14.958608233170475, longitude: -29.799616657329054),
            horizontalAccuracy: 27.400679403751347,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: LocationMotion
                    .Speed(
                        metersPerSecond: 141.15945431116234,
                        accuracyMetersPerSecond: 1.869488358040168,
                    ),
                altitude: LocationMotion.Altitude(
                    meters: 2323.6848056083545,
                    accuracyMeters: 31.141836161711268,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000058")!,
            timestamp: Date(timeIntervalSince1970: 1_577_873_382.080328),
            coordinate: Coordinate(latitude: 14.958608233170475, longitude: -29.799616657329054),
            horizontalAccuracy: 27.400679403751347,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: LocationMotion
                    .Speed(
                        metersPerSecond: 141.15945431116234,
                        accuracyMetersPerSecond: 1.869488358040168,
                    ),
                altitude: LocationMotion.Altitude(
                    meters: 2323.6848056083545,
                    accuracyMeters: 31.141836161711268,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000067")!,
            timestamp: Date(timeIntervalSince1970: 1_577_889_673.0397902),
            coordinate: Coordinate(latitude: 23.941184239727644, longitude: 8.43592951935058),
            horizontalAccuracy: 14.245954591920327,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: LocationMotion
                    .Speed(
                        metersPerSecond: 183.40409843473913,
                        accuracyMetersPerSecond: 1.1278409953211943,
                    ),
                altitude: LocationMotion.Altitude(
                    meters: 5061.671436836012,
                    accuracyMeters: 12.153714711528282,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timestamp: Date(timeIntervalSince1970: 1_577_889_673.0397902),
            coordinate: Coordinate(latitude: 23.941184239727644, longitude: 8.43592951935058),
            horizontalAccuracy: 14.245954591920327,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: LocationMotion
                    .Speed(
                        metersPerSecond: 183.40409843473913,
                        accuracyMetersPerSecond: 1.1278409953211943,
                    ),
                altitude: LocationMotion.Altitude(
                    meters: 5061.671436836012,
                    accuracyMeters: 12.153714711528282,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000044")!,
            timestamp: Date(timeIntervalSince1970: 1_577_890_497.5467381),
            coordinate: Coordinate(latitude: 23.981379987283727, longitude: 8.54307713628467),
            horizontalAccuracy: 39.895013999999996,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: LocationMotion
                    .Speed(metersPerSecond: 66.8244143090688, accuracyMetersPerSecond: 1.0),
                altitude: LocationMotion.Altitude(
                    meters: 82.83155017631483,
                    accuracyMeters: 40.08858402217573,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000041")!,
            timestamp: Date(timeIntervalSince1970: 1_577_890_584.48733),
            coordinate: Coordinate(latitude: 23.979789138728453, longitude: 8.569725745504048),
            horizontalAccuracy: 1000.0,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
            timestamp: Date(timeIntervalSince1970: 1_577_890_584.48733),
            coordinate: Coordinate(latitude: 23.979789138728453, longitude: 8.569725745504048),
            horizontalAccuracy: 1000.0,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            timestamp: Date(timeIntervalSince1970: 1_577_891_199.9787588),
            coordinate: Coordinate(latitude: 23.979936167120144, longitude: 8.568230276514099),
            horizontalAccuracy: 7.879150662684429,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: LocationMotion
                    .Speed(
                        metersPerSecond: 1.6024708762676663,
                        accuracyMetersPerSecond: 1.2293284145646377,
                    ),
                altitude: LocationMotion.Altitude(
                    meters: 4.499187261797488,
                    accuracyMeters: 8.38940753981359,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000023")!,
            timestamp: Date(timeIntervalSince1970: 1_577_891_209.9787588),
            coordinate: Coordinate(latitude: 23.979936167120144, longitude: 8.568230276514099),
            horizontalAccuracy: 7.879150662684429,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: LocationMotion
                    .Speed(
                        metersPerSecond: 1.6024708762676663,
                        accuracyMetersPerSecond: 1.2293284145646377,
                    ),
                altitude: LocationMotion.Altitude(
                    meters: 4.499187261797488,
                    accuracyMeters: 8.38940753981359,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000057")!,
            timestamp: Date(timeIntervalSince1970: 1_577_892_171.275951),
            coordinate: Coordinate(latitude: 23.983891703685945, longitude: 8.567625937142042),
            horizontalAccuracy: 23.395014,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 7.3625019712856625,
                    accuracyMeters: 300.7235745691349,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
            timestamp: Date(timeIntervalSince1970: 1_577_892_284.9462256),
            coordinate: Coordinate(latitude: 23.986776869224823, longitude: 8.56675900709544),
            horizontalAccuracy: 29.07672642645094,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000034")!,
            timestamp: Date(timeIntervalSince1970: 1_577_892_284.9462256),
            coordinate: Coordinate(latitude: 23.986772591838303, longitude: 8.566791421013992),
            horizontalAccuracy: 39.80701302965425,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
            timestamp: Date(timeIntervalSince1970: 1_577_892_606.848868),
            coordinate: Coordinate(latitude: 23.989902365303628, longitude: 8.56857321708371),
            horizontalAccuracy: 52.895013999999996,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 8.412220910544699,
                    accuracyMeters: 300.30206558500385,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000029")!,
            timestamp: Date(timeIntervalSince1970: 1_577_892_948.745228),
            coordinate: Coordinate(latitude: 23.98759669374209, longitude: 8.55996254190055),
            horizontalAccuracy: 52.595014,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000061")!,
            timestamp: Date(timeIntervalSince1970: 1_577_893_248.911629),
            coordinate: Coordinate(latitude: 24.00537601989438, longitude: 8.543648345803946),
            horizontalAccuracy: 49.82277695061683,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 7.9309241382610836,
                    accuracyMeters: 78.1942739024198,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            timestamp: Date(timeIntervalSince1970: 1_577_893_444.697781),
            coordinate: Coordinate(latitude: 24.032572813129345, longitude: 8.527250010613258),
            horizontalAccuracy: 20.06011680172338,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000062")!,
            timestamp: Date(timeIntervalSince1970: 1_577_893_444.697781),
            coordinate: Coordinate(latitude: 24.03274598709049, longitude: 8.52663075930369),
            horizontalAccuracy: 64.69640809321403,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000051")!,
            timestamp: Date(timeIntervalSince1970: 1_577_893_553.060405),
            coordinate: Coordinate(latitude: 24.032268479137926, longitude: 8.526917651819462),
            horizontalAccuracy: 34.095014,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 25.419849543076168,
                    accuracyMeters: 31.1818298726362,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            timestamp: Date(timeIntervalSince1970: 1_577_894_728.847803),
            coordinate: Coordinate(latitude: 24.030182862252857, longitude: 8.519732865009193),
            horizontalAccuracy: 14.386260636057065,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: LocationMotion
                    .Speed(
                        metersPerSecond: 11.616548538208008,
                        accuracyMetersPerSecond: 0.4695776402950287,
                    ),
                altitude: LocationMotion.Altitude(meters: 20.87964605071652, accuracyMeters: 3.0),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000068")!,
            timestamp: Date(timeIntervalSince1970: 1_577_895_029.7008119),
            coordinate: Coordinate(latitude: 24.04380747377919, longitude: 8.491058315099888),
            horizontalAccuracy: 1000.0,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(meters: 23.97365785908397, accuracyMeters: 3.0),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000060")!,
            timestamp: Date(timeIntervalSince1970: 1_577_895_338.2156382),
            coordinate: Coordinate(latitude: 24.056255511763855, longitude: 8.428880022876964),
            horizontalAccuracy: 1000.0,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(meters: 15.653657859083978, accuracyMeters: 3.0),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!,
            timestamp: Date(timeIntervalSince1970: 1_577_895_682.375444),
            coordinate: Coordinate(latitude: 24.03716453736034, longitude: 8.368488322975317),
            horizontalAccuracy: 2000.0,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(meters: -1.1802392356425457, accuracyMeters: 3.0),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!,
            timestamp: Date(timeIntervalSince1970: 1_577_895_740.476544),
            coordinate: Coordinate(latitude: 24.037252902316922, longitude: 8.365179259640453),
            horizontalAccuracy: 130.99302654075407,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000037")!,
            timestamp: Date(timeIntervalSince1970: 1_577_895_740.476544),
            coordinate: Coordinate(latitude: 24.037408725455744, longitude: 8.365257818533689),
            horizontalAccuracy: 91.6977959582399,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000063")!,
            timestamp: Date(timeIntervalSince1970: 1_577_896_505.9222121),
            coordinate: Coordinate(latitude: 24.061144283864017, longitude: 8.364576765299976),
            horizontalAccuracy: 1000.0,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 21.65732473922295,
                    accuracyMeters: 5.6223842414580885,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            timestamp: Date(timeIntervalSince1970: 1_577_896_505.9222121),
            coordinate: Coordinate(latitude: 24.061144283864017, longitude: 8.364576765299976),
            horizontalAccuracy: 1000.0,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 21.65732473922295,
                    accuracyMeters: 5.6223842414580885,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000054")!,
            timestamp: Date(timeIntervalSince1970: 1_577_896_734.2992172),
            coordinate: Coordinate(latitude: 24.06395099680245, longitude: 8.3630700016351),
            horizontalAccuracy: 20.596014,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000016")!,
            timestamp: Date(timeIntervalSince1970: 1_577_901_532.077001),
            coordinate: Coordinate(latitude: 24.065202542808372, longitude: 8.36254582564184),
            horizontalAccuracy: 12.863668683294195,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 22.769760764357443,
                    accuracyMeters: 4.4104850019447746,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            timestamp: Date(timeIntervalSince1970: 1_577_901_538.525515),
            coordinate: Coordinate(latitude: 24.06519262368378, longitude: 8.362553685800139),
            horizontalAccuracy: 11.925727188885794,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 22.769760764357443,
                    accuracyMeters: 4.42448244986533,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            timestamp: Date(timeIntervalSince1970: 1_577_907_350.7798781),
            coordinate: Coordinate(latitude: 24.065234377063987, longitude: 8.36237358535109),
            horizontalAccuracy: 39.93764131963068,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 20.49976076435746,
                    accuracyMeters: 7.307660182598929,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000069")!,
            timestamp: Date(timeIntervalSince1970: 1_577_907_841.5096421),
            coordinate: Coordinate(latitude: 24.064874934841523, longitude: 8.3626445132432),
            horizontalAccuracy: 68.67728438631262,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000047")!,
            timestamp: Date(timeIntervalSince1970: 1_577_908_056.5096622),
            coordinate: Coordinate(latitude: 24.0605555469381, longitude: 8.364676732387823),
            horizontalAccuracy: 59.81174645285385,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 15.679760764357411,
                    accuracyMeters: 7.675488967545555,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
            timestamp: Date(timeIntervalSince1970: 1_577_908_489.079418),
            coordinate: Coordinate(latitude: 24.05604233320322, longitude: 8.363839724952518),
            horizontalAccuracy: 19.74299752806734,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 15.679760764357411,
                    accuracyMeters: 7.925271846060376,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000052")!,
            timestamp: Date(timeIntervalSince1970: 1_577_908_604.9317389),
            coordinate: Coordinate(latitude: 24.055884055958586, longitude: 8.363722497169269),
            horizontalAccuracy: 201.4400005418428,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000066")!,
            timestamp: Date(timeIntervalSince1970: 1_577_908_939.493524),
            coordinate: Coordinate(latitude: 24.051541188831067, longitude: 8.362852076004843),
            horizontalAccuracy: 29.414947145647727,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 9.559760764357407,
                    accuracyMeters: 8.148686210463463,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000026")!,
            timestamp: Date(timeIntervalSince1970: 1_577_909_368.4257998),
            coordinate: Coordinate(latitude: 24.047082032661756, longitude: 8.362053307433358),
            horizontalAccuracy: 31.33962194560417,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 1.3097607643574065,
                    accuracyMeters: 8.37810207537697,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000028")!,
            timestamp: Date(timeIntervalSince1970: 1_577_909_880.108097),
            coordinate: Coordinate(latitude: 24.04231560939558, longitude: 8.360980889930016),
            horizontalAccuracy: 39.9877947967888,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: -1.2102392356425753,
                    accuracyMeters: 8.641223111860509,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000048")!,
            timestamp: Date(timeIntervalSince1970: 1_577_910_224.818527),
            coordinate: Coordinate(latitude: 24.04134020640819, longitude: 8.361068976063855),
            horizontalAccuracy: 113.86750490563072,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000075")!,
            timestamp: Date(timeIntervalSince1970: 1_577_910_456.221107),
            coordinate: Coordinate(latitude: 24.03960781024593, longitude: 8.365005558485636),
            horizontalAccuracy: 25.595014,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 0.6638583395168512,
                    accuracyMeters: 20.16794506273759,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000049")!,
            timestamp: Date(timeIntervalSince1970: 1_577_910_527.639421),
            coordinate: Coordinate(latitude: 24.03850155209335, longitude: 8.368629540349222),
            horizontalAccuracy: 31.796014,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!,
            timestamp: Date(timeIntervalSince1970: 1_577_914_295.1339562),
            coordinate: Coordinate(latitude: 24.03846568748061, longitude: 8.368723421356481),
            horizontalAccuracy: 71.16917586999561,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000071")!,
            timestamp: Date(timeIntervalSince1970: 1_577_914_466.222434),
            coordinate: Coordinate(latitude: 24.042026450579982, longitude: 8.369236155402634),
            horizontalAccuracy: 28.152257430781525,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 4.8097607643574065,
                    accuracyMeters: 11.114794245618212,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000018")!,
            timestamp: Date(timeIntervalSince1970: 1_577_914_748.5397325),
            coordinate: Coordinate(latitude: 24.047193743179275, longitude: 8.370071580048343),
            horizontalAccuracy: 96.96187802275803,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000046")!,
            timestamp: Date(timeIntervalSince1970: 1_577_914_748.5397325),
            coordinate: Coordinate(latitude: 24.048043496892557, longitude: 8.370404640511412),
            horizontalAccuracy: 9.930101374469094,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000076")!,
            timestamp: Date(timeIntervalSince1970: 1_577_914_911.11034),
            coordinate: Coordinate(latitude: 24.04648070499119, longitude: 8.369973540264548),
            horizontalAccuracy: 26.93142610617376,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 2.7897607643574247,
                    accuracyMeters: 11.361716344685354,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000073")!,
            timestamp: Date(timeIntervalSince1970: 1_577_915_387.340224),
            coordinate: Coordinate(latitude: 24.0508921505758, longitude: 8.37106711561525),
            horizontalAccuracy: 30.525164088933654,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: 2.16976076435742,
                    accuracyMeters: 11.60838054698539,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000045")!,
            timestamp: Date(timeIntervalSince1970: 1_577_915_418.6828752),
            coordinate: Coordinate(latitude: 24.053754590852567, longitude: 8.37161784412596),
            horizontalAccuracy: 18.496014,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000039")!,
            timestamp: Date(timeIntervalSince1970: 1_577_915_418.6828752),
            coordinate: Coordinate(latitude: 24.054798583226244, longitude: 8.371986142051117),
            horizontalAccuracy: 15.996014,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
            timestamp: Date(timeIntervalSince1970: 1_577_915_865.453446),
            coordinate: Coordinate(latitude: 24.055324267609894, longitude: 8.372002226277173),
            horizontalAccuracy: 29.234931746967657,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: -0.14023923564258212,
                    accuracyMeters: 11.87154025578009,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000055")!,
            timestamp: Date(timeIntervalSince1970: 1_577_916_266.687928),
            coordinate: Coordinate(latitude: 24.057730096238338, longitude: 8.367551169911005),
            horizontalAccuracy: 48.17703812528123,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(
                    meters: -0.14023923564258212,
                    accuracyMeters: 12.090938040807496,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            timestamp: Date(timeIntervalSince1970: 1_577_916_323.5846162),
            coordinate: Coordinate(latitude: 24.061427781384477, longitude: 8.369144336491258),
            horizontalAccuracy: 45.874238077871745,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            timestamp: Date(timeIntervalSince1970: 1_577_916_649.091897),
            coordinate: Coordinate(latitude: 24.063519394319147, longitude: 8.367041279403088),
            horizontalAccuracy: 7.4266319593192165,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000036")!,
            timestamp: Date(timeIntervalSince1970: 1_577_916_649.091897),
            coordinate: Coordinate(latitude: 24.0636396210738, longitude: 8.365847659433655),
            horizontalAccuracy: 25.196014,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000053")!,
            timestamp: Date(timeIntervalSince1970: 1_577_916_670.61057),
            coordinate: Coordinate(latitude: 24.062576227251093, longitude: 8.368391532702006),
            horizontalAccuracy: 52.77781315629399,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(meters: 29.42012176906536, accuracyMeters: 3.0),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
            timestamp: Date(timeIntervalSince1970: 1_577_917_299.010689),
            coordinate: Coordinate(latitude: 24.063654703517013, longitude: 8.363616104103547),
            horizontalAccuracy: 14.511513582615335,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: LocationMotion
                    .Speed(metersPerSecond: 0.0, accuracyMetersPerSecond: 1.1198837757110596),
                altitude: LocationMotion.Altitude(
                    meters: 25.25267543106079,
                    accuracyMeters: 10.686976432800293,
                ),
            ),
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000025")!,
            timestamp: Date(timeIntervalSince1970: 1_577_917_390.715047),
            coordinate: Coordinate(latitude: 24.065402218564984, longitude: 8.362923717848025),
            horizontalAccuracy: 16.535835676707528,
            source: .gpsVisit,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: nil,
        ),
        LocationSample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000038")!,
            timestamp: Date(timeIntervalSince1970: 1_577_918_655.072243),
            coordinate: Coordinate(latitude: 24.06328964074408, longitude: 8.363164828703995),
            horizontalAccuracy: 20.0,
            source: .gpsSignificantChange,
            recordingDeviceID: RecordingDeviceID(
                rawValue: UUID(uuidString: "00000001-0000-0000-0000-000000000001")!,
            ),
            motion: LocationMotion(
                speed: nil,
                altitude: LocationMotion.Altitude(meters: 60.05296023808366, accuracyMeters: 30.0),
            ),
        ),
    ]
}
