import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

/// One day in the month grid: the day number, region-presence dots beneath it,
/// and a subtle region-tinted "stay" pill behind it that connects to adjacent
/// days in the same run so a stretch in one place reads as a single shape.
struct DayCell: View {
    let day: CalendarDayCell
    /// The stay-pill slice for this day (computed by the enclosing month).
    let band: DayBandGeometry
    let dateCalendar: Calendar
    var compact = false
    var isAvailable = true

    @Environment(\.stylesheet) private var stylesheet

    private var calendar: WhereStylesheet.CalendarStyle {
        compact ? stylesheet.calendar.compact : stylesheet.calendar
    }

    var body: some View {
        VStack(spacing: calendar.day.numberDotSpacing) {
            CalendarDayNumber(
                day: day,
                compact: compact,
                style: calendar.day,
                color: dayNumberColor,
            )
            CalendarRegionDots(band: band, style: calendar.day)
        }
        // Pad the content, then back it with the pill so the pill hugs the
        // content with a little vertical breathing room (rather than butting
        // into the dots); the outer frame is the tap target.
        .frame(maxWidth: .infinity)
        .padding(.vertical, calendar.regionBand.verticalInset)
        .background {
            CalendarStayPill(
                band: band,
                style: calendar.regionBand,
                gridSpacing: calendar.month.gridSpacing,
            )
        }
        .frame(minHeight: calendar.day.minHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.date.formatted(Date.FormatStyle(
            date: .complete,
            time: .omitted,
            calendar: dateCalendar,
            timeZone: dateCalendar.timeZone,
        )))
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var values = band.regions.map { region in
            guard let membership = band.memberships[region] else { return region.localizedName }
            return String(localized: .planningCalendarMonthSummary(
                region.localizedName,
                WhereFormat.planningMembership(membership),
            ))
        }
        if day.hasEvidence {
            values.append(String(localized: .calendarAttachmentAccessibility))
        }
        if day.hasFlight {
            values.append(String(localized: .historyFlight))
        }
        return values.joined(separator: "; ")
    }

    private var dayNumberColor: Color {
        if day.isToday {
            calendar.day.todayNumberColor
        } else if day.needsAttention {
            calendar.day.unresolvedNumberColor
        } else {
            isAvailable ? .primary : calendar.overview.unavailableForeground
        }
    }
}

private struct CalendarDayNumber: View {
    let day: CalendarDayCell
    let compact: Bool
    let style: WhereStylesheet.CalendarStyle.DayStyle
    let color: Color

    var body: some View {
        Text("\(day.dayOfMonth)")
            .font(.system(size: style.numberFontSize))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(color)
            .frame(
                width: compact ? nil : style.numberSize,
                height: style.numberSize,
            )
            .background {
                CalendarDayMarker(day: day, style: style)
            }
            .overlay(alignment: .topTrailing) {
                if !compact, day.hasEvidence || day.hasFlight {
                    CalendarDayBadges(day: day, style: style)
                }
            }
    }
}

private struct CalendarDayMarker: View {
    let day: CalendarDayCell
    let style: WhereStylesheet.CalendarStyle.DayStyle

    var body: some View {
        if day.isToday {
            Circle()
                .fill(style.todayMarker)
        } else if day.needsAttention {
            Circle()
                .fill(style.unresolvedMarker)
        }
    }
}

private struct CalendarDayBadges: View {
    let day: CalendarDayCell
    let style: WhereStylesheet.CalendarStyle.DayStyle

    var body: some View {
        HStack(spacing: style.badge.iconSpacing) {
            if day.hasEvidence {
                badgeIcon(.paperclip)
            }
            if day.hasFlight {
                badgeIcon(.airplane)
            }
        }
        .foregroundStyle(Color.accentColor)
        .padding(style.badge.padding)
        .background(Capsule().fill(Color(.systemBackground)))
        // Keep the first icon at the corner; additional icons
        // extend to the right without covering the day number.
        .offset(badgeOffset)
    }

    private var badgeOffset: CGSize {
        let extraWidth = day.hasEvidence && day.hasFlight
            ? style.badge.iconSize + style.badge.iconSpacing
            : 0
        return CGSize(
            width: style.badge.offset.width + extraWidth,
            height: style.badge.offset.height,
        )
    }

    private func badgeIcon(_ symbol: SFSymbol) -> some View {
        Image(systemSymbol: symbol)
            .font(.system(size: style.badge.iconSize, weight: .bold))
            .frame(width: style.badge.iconSize, height: style.badge.iconSize)
    }
}

/// Region-presence dots beneath the day number (one per region the day
/// counts for), each with a subtle background-colored rim. On a multi-region
/// day the dots overlap into a cluster, the rims keeping them distinct.
/// Empty days keep the row height so the grid baseline is even.
private struct CalendarRegionDots: View {
    let band: DayBandGeometry
    let style: WhereStylesheet.CalendarStyle.DayStyle

    var body: some View {
        let isCluster = band.regions.count > 1
        HStack(spacing: isCluster ? -style.dotOverlap : style.contentSpacing) {
            ForEach(band.regions, id: \.self) { region in
                CalendarRegionDot(
                    region: region,
                    membership: band.memberships[region],
                    style: style,
                )
            }
        }
        .frame(height: style.dotSize)
    }
}

private struct CalendarRegionDot: View {
    let region: Region
    let membership: PlanningDayPresence.Membership?
    let style: WhereStylesheet.CalendarStyle.DayStyle
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        Group {
            switch membership {
                case .homeAssumed:
                    Image(systemSymbol: .houseFill)
                        .resizable()
                        .scaledToFit()
                case .planned(.possible):
                    Circle().strokeBorder(lineWidth: style.dotStrokeWidth)
                case .planned(.certain), nil:
                    Circle()
            }
        }
        .foregroundStyle(regionStyles.style(for: region).tint)
        .frame(width: style.dotSize, height: style.dotSize)
    }
}

/// The subtle region-tinted pill spanning this day's slice of a stay run —
/// tinted per region (a soft blend on multi-region days), its corners
/// rounded per `band`, inset vertically, and bled `extend…` points into the
/// grid gaps so same-run neighbours join into one shape. A `GeometryReader`
/// gives the exact cell size to size and offset the overflow precisely.
private struct CalendarStayPill: View {
    let band: DayBandGeometry
    let style: WhereStylesheet.CalendarStyle.RegionBand
    let gridSpacing: CGFloat

    var body: some View {
        if !band.regions.isEmpty {
            GeometryReader { proxy in
                CalendarStayPillSlice(
                    band: band,
                    style: style,
                    cellSize: proxy.size,
                    gridSpacing: gridSpacing,
                )
            }
        }
    }
}

private struct CalendarStayPillSlice: View {
    let band: DayBandGeometry
    let style: WhereStylesheet.CalendarStyle.RegionBand
    let cellSize: CGSize
    let gridSpacing: CGFloat
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        ZStack {
            shape.fill(pillFill).opacity(band.isPlanned ? style.planned.fillOpacity : style.opacity)
            if band.isPlanned {
                CalendarStayPillHatch(
                    shape: shape,
                    color: firstRegionColor,
                    style: style.planned,
                    gridOriginX: gridOriginX,
                )
            }
            if band.hasPossible {
                shape.strokeBorder(firstRegionColor, style: possibleStroke)
            }
        }
        .frame(
            width: cellSize.width + band.extendLeading + band.extendTrailing,
            height: cellSize.height,
        )
        .offset(x: -band.extendLeading)
    }

    private var gridOriginX: CGFloat {
        CGFloat(band.column) * (cellSize.width + gridSpacing) - band.extendLeading
    }

    private var possibleStroke: StrokeStyle {
        StrokeStyle(lineWidth: style.planned.hatchLineWidth, dash: [style.planned.hatchSpacing])
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: band.leadingRadius,
            bottomLeadingRadius: band.leadingRadius,
            bottomTrailingRadius: band.trailingRadius,
            topTrailingRadius: band.trailingRadius,
        )
    }

    private var firstRegionColor: Color {
        band.regions.first.map { regionStyles.style(for: $0).tint } ?? .accentColor
    }

    /// The pill's tint: one region reads as a solid wash; a multi-region day
    /// (rare — a travel day) softly blends its regions left-to-right.
    private var pillFill: LinearGradient {
        LinearGradient(
            colors: band.regions.map { regionStyles.style(for: $0).tint },
            startPoint: .leading,
            endPoint: .trailing,
        )
    }
}

private struct CalendarStayPillHatch: View {
    let shape: UnevenRoundedRectangle
    let color: Color
    let style: WhereStylesheet.CalendarStyle.RegionBand.Planned
    let gridOriginX: CGFloat

    var body: some View {
        PlannedStayHatch(
            color: color,
            spacing: style.hatchSpacing,
            lineWidth: style.hatchLineWidth,
            gridOriginX: gridOriginX,
        )
        .opacity(style.hatchOpacity)
        .clipShape(shape)
    }
}

/// How to draw a day's slice of the region "stay" pill: which corners round
/// (the run's ends) and how far to bleed into the grid gaps so a run reads as
/// one connected shape. Empty `regions` means no pill.
struct DayBandGeometry {
    var regions: [Region]
    var memberships: [Region: PlanningDayPresence.Membership]
    var isPlanned: Bool {
        !memberships.isEmpty
    }

    var hasPossible: Bool {
        memberships.values.contains { membership in
            switch membership {
                case .planned(.possible), .homeAssumed(.possible): true
                case .planned(.certain), .homeAssumed(.certain): false
            }
        }
    }

    var column: Int
    var leadingRadius: CGFloat
    var trailingRadius: CGFloat
    var extendLeading: CGFloat
    var extendTrailing: CGFloat

    static let none = DayBandGeometry(
        regions: [],
        memberships: [:],
        column: 0,
        leadingRadius: 0,
        trailingRadius: 0,
        extendLeading: 0,
        extendTrailing: 0,
    )
}

#if DEBUG
    #Preview("Flight and evidence") {
        let calendar = Calendar(identifier: .gregorian)
        let month = PreviewSupport.calendarAccessibilityMonth(calendar: calendar)
        if let day = month.days.first(where: { $0.hasFlight && $0.hasEvidence }) {
            DayCell(day: day, band: .none, dateCalendar: calendar)
                .frame(width: 44)
                .whereBroadwayRoot()
        }
    }
#endif
