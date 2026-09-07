import Foundation

/// Offline NOAA fractional-year solar equations, using the conventional 90.833° sunrise zenith.
/// Source: https://www.gml.noaa.gov/grad/solcalc/solareqns.PDF
public struct SolarCalculator: SolarCalculating {
    public init() {}

    public func events(on date: Date, site: CaptureSettings.Site) throws -> [SolarEvent] {
        var settings = CaptureSettings.standard
        settings.site = site
        try settings.validate()
        guard let zone = TimeZone(identifier: site.timeZoneIdentifier)
        else { throw DaylightError.invalidSettings }
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        let components = local.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month,
              let day = components.day else { throw DaylightError.invalidSettings }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        guard let base = utc.date(from: DateComponents(year: year, month: month, day: day)),
              let ordinal = utc.ordinality(of: .day, in: .year, for: base),
              let days = utc.range(of: .day, in: .year, for: base)
        else { throw DaylightError.invalidSettings }
        let gamma = 2 * Double.pi / Double(days.count) * Double(ordinal - 1)
        let equation = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let declination = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let latitude = site.latitude * .pi / 180
        let cosine = cos(90.833 * .pi / 180) / (cos(latitude) * cos(declination)) - tan(latitude) *
            tan(declination)
        guard (-1 ... 1).contains(cosine) else { return [] }
        let angle = acos(cosine) * 180 / .pi
        let localDay = local.dateInterval(of: .day, for: date)
        guard let localDay else { throw DaylightError.invalidSettings }
        return try SolarEvent.Kind.allCases.map { kind in
            let sign: Double = kind == .sunrise ? 1 : -1
            let minutes = 720 - 4 * (site.longitude + sign * angle) - equation
            let estimate = base.addingTimeInterval(minutes * 60)
            // Civil zones can lie on the opposite side of the international date line from
            // longitude.
            guard let eventDate = [-86400.0, 0, 86400].map({ estimate.addingTimeInterval($0) })
                .first(where: { $0 >= localDay.start && $0 < localDay.end })
            else { throw DaylightError.invalidSettings }
            return SolarEvent(
                id: .init(year: year, month: month, day: day, kind: kind),
                date: eventDate,
            )
        }
    }
}
