import Foundation
import RegionKit
import WhereCore

/// Scripts a year-long sequence of `LocationSample`s, manual day entries,
/// and evidence attachments into a `WhereServices`. The output is the
/// fixture both unit assertions and snapshot tests read from.
///
/// Designed so the day arithmetic is easy to eyeball:
///
/// - 12 months of consecutive 1-region residency stretches.
/// - 8 dual-region "flight days" (each appears in two regional buckets).
/// - One 7-day no-GPS gap (Sep 16–22) that should be **absent** from the
///   report.
/// - One stretch with no GPS but with retroactive manual day entries
///   (Nov 8–12 set to `.california`), plus a smaller 2-day gap (Nov 13–14)
///   that stays absent.
/// - 3 evidence attachments tied to the most interesting trips.
enum SimulatedYear {
    static let year = 2026

    static func script(services: WhereServices, calendar: Calendar) async {
        let sf = (lat: 37.7749, lng: -122.4194)
        let la = (lat: 34.0522, lng: -118.2437)
        let nyc = (lat: 40.7128, lng: -74.0060)
        let paris = (lat: 48.8566, lng: 2.3522)
        let toronto = (lat: 43.6532, lng: -79.3832)

        // Collect the whole year of GPS samples, then persist them in a single
        // batch (one transaction, one widget-snapshot rebuild) below — see the
        // `services.journal.ingest(samples)` call after the day scripting.
        var samples: [LocationSample] = []

        func emitNoon(month: Int, day: Int, lat: Double, lng: Double) async {
            samples.append(Self.sample(
                calendar: calendar,
                month: month,
                day: day,
                hour: 12,
                lat: lat,
                lng: lng,
            ))
        }

        func emitFlight(
            month: Int,
            day: Int,
            originLat: Double,
            originLng: Double,
            destLat: Double,
            destLng: Double,
        ) async {
            samples.append(Self.sample(
                calendar: calendar,
                month: month,
                day: day,
                hour: 6,
                lat: originLat,
                lng: originLng,
            ))
            samples.append(Self.sample(
                calendar: calendar,
                month: month,
                day: day,
                hour: 20,
                lat: destLat,
                lng: destLng,
            ))
        }

        // Jan: SF (31 days)
        for d in 1 ... 31 {
            await emitNoon(month: 1, day: d, lat: sf.lat, lng: sf.lng)
        }
        // Feb: LA (28 days)
        for d in 1 ... 28 {
            await emitNoon(month: 2, day: d, lat: la.lat, lng: la.lng)
        }
        // Mar: SF -> NYC mid-month
        for d in 1 ... 15 {
            await emitNoon(month: 3, day: d, lat: sf.lat, lng: sf.lng)
        }
        await emitFlight(
            month: 3,
            day: 16,
            originLat: sf.lat,
            originLng: sf.lng,
            destLat: nyc.lat,
            destLng: nyc.lng,
        )
        for d in 17 ... 31 {
            await emitNoon(month: 3, day: d, lat: nyc.lat, lng: nyc.lng)
        }
        // Apr: NYC -> SF mid-month
        for d in 1 ... 15 {
            await emitNoon(month: 4, day: d, lat: nyc.lat, lng: nyc.lng)
        }
        await emitFlight(
            month: 4,
            day: 16,
            originLat: nyc.lat,
            originLng: nyc.lng,
            destLat: sf.lat,
            destLng: sf.lng,
        )
        for d in 17 ... 30 {
            await emitNoon(month: 4, day: d, lat: sf.lat, lng: sf.lng)
        }
        // May: SF -> NYC -> Paris -> NYC
        for d in 1 ... 14 {
            await emitNoon(month: 5, day: d, lat: sf.lat, lng: sf.lng)
        }
        await emitFlight(
            month: 5,
            day: 15,
            originLat: sf.lat,
            originLng: sf.lng,
            destLat: nyc.lat,
            destLng: nyc.lng,
        )
        await emitNoon(month: 5, day: 16, lat: nyc.lat, lng: nyc.lng)
        for d in 17 ... 28 {
            await emitNoon(month: 5, day: d, lat: paris.lat, lng: paris.lng)
        }
        await emitFlight(
            month: 5,
            day: 29,
            originLat: paris.lat,
            originLng: paris.lng,
            destLat: nyc.lat,
            destLng: nyc.lng,
        )
        for d in 30 ... 31 {
            await emitNoon(month: 5, day: d, lat: nyc.lat, lng: nyc.lng)
        }
        // Jun: NYC -> Toronto -> NYC
        for d in 1 ... 15 {
            await emitNoon(month: 6, day: d, lat: nyc.lat, lng: nyc.lng)
        }
        await emitFlight(
            month: 6,
            day: 16,
            originLat: nyc.lat,
            originLng: nyc.lng,
            destLat: toronto.lat,
            destLng: toronto.lng,
        )
        for d in 17 ... 21 {
            await emitNoon(month: 6, day: d, lat: toronto.lat, lng: toronto.lng)
        }
        await emitFlight(
            month: 6,
            day: 22,
            originLat: toronto.lat,
            originLng: toronto.lng,
            destLat: nyc.lat,
            destLng: nyc.lng,
        )
        for d in 23 ... 30 {
            await emitNoon(month: 6, day: d, lat: nyc.lat, lng: nyc.lng)
        }
        // Jul: NYC -> SF mid-month
        for d in 1 ... 15 {
            await emitNoon(month: 7, day: d, lat: nyc.lat, lng: nyc.lng)
        }
        await emitFlight(
            month: 7,
            day: 16,
            originLat: nyc.lat,
            originLng: nyc.lng,
            destLat: sf.lat,
            destLng: sf.lng,
        )
        for d in 17 ... 31 {
            await emitNoon(month: 7, day: d, lat: sf.lat, lng: sf.lng)
        }
        // Aug: SF
        for d in 1 ... 31 {
            await emitNoon(month: 8, day: d, lat: sf.lat, lng: sf.lng)
        }
        // Sep: SF with a 7-day no-GPS gap (16-22)
        for d in 1 ... 15 {
            await emitNoon(month: 9, day: d, lat: sf.lat, lng: sf.lng)
        }
        for d in 23 ... 30 {
            await emitNoon(month: 9, day: d, lat: sf.lat, lng: sf.lng)
        }
        // Oct: SF
        for d in 1 ... 31 {
            await emitNoon(month: 10, day: d, lat: sf.lat, lng: sf.lng)
        }
        // Nov: SF, then a no-GPS stretch backfilled retroactively, then a real 2-day gap
        for d in 1 ... 7 {
            await emitNoon(month: 11, day: d, lat: sf.lat, lng: sf.lng)
        }
        for d in 8 ... 12 {
            let date = calendar.date(from: DateComponents(year: year, month: 11, day: d)) ?? Date()
            try? await services.journal.addManualDay(date: date, regions: [.california], audit: nil)
        }
        for d in 15 ... 30 {
            await emitNoon(month: 11, day: d, lat: sf.lat, lng: sf.lng)
        }
        // Dec: SF -> NYC mid-month
        for d in 1 ... 15 {
            await emitNoon(month: 12, day: d, lat: sf.lat, lng: sf.lng)
        }
        await emitFlight(
            month: 12,
            day: 16,
            originLat: sf.lat,
            originLng: sf.lng,
            destLat: nyc.lat,
            destLng: nyc.lng,
        )
        for d in 17 ... 31 {
            await emitNoon(month: 12, day: d, lat: nyc.lat, lng: nyc.lng)
        }

        // Persist the entire year's GPS in one transaction so the widget
        // snapshot is rebuilt once rather than once per sample.
        try? await services.journal.ingest(samples)

        // Evidence attachments. UUIDs are deterministic so any future snapshot
        // of evidence stays stable.
        let evidences: [(
            month: Int,
            day: Int,
            kind: EvidenceKind,
            note: String,
            region: Region,
            uuid: String
        )] = [
            (
                3,
                16,
                .planeTicket,
                "SFO → JFK transcontinental",
                .california,
                "00000000-0000-0000-0000-000000000316"
            ),
            (
                5,
                17,
                .boardingPass,
                "JFK → CDG overnight",
                .europeanUnion,
                "00000000-0000-0000-0000-000000000517"
            ),
            (
                6,
                16,
                .planeTicket,
                "LGA → YYZ Toronto trip",
                .canada,
                "00000000-0000-0000-0000-000000000616"
            ),
        ]
        for entry in evidences {
            let date = calendar.date(
                from: DateComponents(year: year, month: entry.month, day: entry.day, hour: 8),
            ) ?? Date()
            let id = UUID(uuidString: entry.uuid) ?? UUID()
            try? await services.journal.addEvidence(
                Evidence(
                    id: id,
                    kind: entry.kind,
                    capturedAt: date,
                    region: entry.region,
                    note: entry.note,
                    contentType: .other(nil),
                ),
                blob: nil,
            )
        }
    }

    private static func sample(
        calendar: Calendar,
        month: Int,
        day: Int,
        hour: Int,
        lat: Double,
        lng: Double,
    ) -> LocationSample {
        let date = calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour),
        ) ?? Date()
        return LocationSample(
            timestamp: date,
            coordinate: Coordinate(latitude: lat, longitude: lng),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        )
    }
}
