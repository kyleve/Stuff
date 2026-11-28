import RegionKit
import SwiftUI
import WhereCore

/// Renders the loaded calendar. Its screen owns the two scroll positions and zoom commands.
struct CalendarScrollView: View {
    typealias Target = CalendarPresentationState.Target
    let months: [CalendarMonth]
    let report: YearReportModel
    let focusedRegion: Region?
    let forecasts: [LocationForecast]
    let showsEstimateCard: Bool
    let presentation: CalendarPresentationState
    let zoom: CalendarZoomTransitionState
    let position: Binding<ScrollPosition>
    let focusedTarget: AccessibilityFocusState<Target?>.Binding
    @Binding var scrollOffset: CGPoint
    let onExpand: (Target) -> Void
    let onPinch: (CGFloat, Target?) -> Void
    let onPlan: () -> Void
    let restorePosition: (Target?) -> Void
    let onPresentationReady: (() -> Void)?
    let finishZoom: (CalendarZoomTransitionState.ID) -> Void

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let availableMonths = CalendarModel.visibleMonths(
            months,
            report: report,
            focusedRegion: focusedRegion,
        )
        let currentMonth = months.first(where: \.isCurrentMonth)
        let estimateMonth = showsEstimateCard && report.showsEstimatedTimeAndPlanning && !forecasts
            .isEmpty
            ? currentMonth : nil
        let overview = presentation.mode == .overview

        ScrollView {
            Group {
                if overview {
                    CalendarOverviewGrid(
                        months: months,
                        availableMonths: availableMonths,
                        estimateMonth: estimateMonth,
                        report: report,
                        focusedRegion: focusedRegion,
                        forecasts: forecasts,
                        presentation: presentation,
                        onExpand: onExpand,
                    )
                } else {
                    CalendarDetailMonths(
                        months: availableMonths,
                        estimateMonth: estimateMonth,
                        report: report,
                        focusedRegion: focusedRegion,
                        forecasts: forecasts,
                        focusedTarget: focusedTarget,
                        onPlan: onPlan,
                    )
                }
            }
            .padding()
            .whereContentRoot()
            // Keep the content origin at the full scroll width so zoom measurements
            // retain the centered column's horizontal offset.
            .transformAnchorPreference(
                key: CalendarZoomFrames.self,
                value: .bounds,
            ) { frames, content in
                frames[overview ? .overview : .detail, default: [:]][.content] = content
            }
        }
        // Each mode keeps its own binding while outgoing content finishes its transition.
        .scrollPosition(position)
        .id(presentation.mode)
        .transition(stylesheet.calendar.overview.transition)
        .onScrollGeometryChange(for: CGPoint.self) {
            CGPoint(
                x: $0.contentOffset.x + $0.contentInsets.leading,
                y: $0.contentOffset.y + $0.contentInsets.top,
            )
        } action: { _, value in
            scrollOffset = value
        }
        .simultaneousGesture(MagnifyGesture().onEnded { value in
            onPinch(value.magnification, target(at: value.startAnchor))
        })
        .sensoryFeedback(.impact(weight: .light), trigger: presentation.rejectionTrigger)
        .onChange(of: presentation.rejectionTrigger) {
            AccessibilityNotification.Announcement(String(localized: .calendarMonthUnavailable))
                .post()
        }
        .task(id: CalendarLayoutID(
            year: report.selectedYear,
            mode: presentation.mode,
            availableMonths: availableMonths.map(\.firstCalendarDay),
            estimateMonth: estimateMonth.map(\.firstCalendarDay),
        )) {
            guard !Task.isCancelled else { return }
            presentation.reconcile(
                year: report.selectedYear,
                availableMonths: availableMonths.map(\.firstCalendarDay),
                estimateMonth: estimateMonth.map(\.firstCalendarDay),
            )
            let initialTarget = estimateMonth
                .map { CalendarPresentationState.Target.estimate($0.firstCalendarDay) }
                ?? (currentMonth ?? availableMonths.last)
                .map { CalendarPresentationState.Target.month($0.firstCalendarDay) }
            restorePosition(initialTarget)
        }
        // Hide the live tiles while their copies move, leaving the page background visible.
        .opacity(zoom.phase == nil ? 1 : 0)
        .overlayPreferenceValue(CalendarZoomFrames.self) { anchors in
            let canReveal = onPresentationReady != nil && presentation.year == report.selectedYear
            CalendarZoomMeasurement(
                anchors: anchors[overview ? .overview : .detail] ?? [:],
                mode: overview ? .overview : .detail,
                scrollOffset: scrollOffset,
                zoom: zoom,
                canReveal: canReveal,
                onPresentationReady: onPresentationReady,
            )
        }
        .allowsHitTesting(zoom.phase == nil)
        .accessibilityHidden(zoom.phase != nil)
        .overlay {
            if let phase = zoom.phase {
                CalendarZoomOverlay(phase: phase) { target, mode in
                    CalendarZoomTile(
                        target: target,
                        mode: mode,
                        months: months,
                        report: report,
                        focusedRegion: focusedRegion,
                        presentation: presentation,
                        forecasts: forecasts,
                        onPlan: onPlan,
                    )
                } completion: { id in
                    finishZoom(id)
                }
            }
        }
    }

    private func target(at startAnchor: UnitPoint) -> Target? {
        let viewportSize = zoom.measurement?.viewport.size ?? .zero
        let point = CGPoint(
            x: startAnchor.x * viewportSize.width,
            y: startAnchor.y * viewportSize.height,
        )
        return (zoom.measurement?.frames ?? [:])
            .first(where: {
                $0.key.month.year == report.selectedYear && $0.value.contains(point)
            })?.key
    }

    private struct CalendarLayoutID: Equatable {
        let year: Int
        let mode: CalendarPresentationState.Mode
        let availableMonths: [CalendarDay]
        let estimateMonth: CalendarDay?
    }
}

extension CalendarMonth {
    var firstCalendarDay: CalendarDay {
        CalendarDay(year: year, month: month, day: 1)
    }
}

private struct CalendarZoomMeasurement: View {
    let anchors: [CalendarZoomFrames.Frame: Anchor<CGRect>]
    let mode: CalendarPresentationState.Mode
    let scrollOffset: CGPoint
    let zoom: CalendarZoomTransitionState
    let canReveal: Bool
    let onPresentationReady: (() -> Void)?

    var body: some View {
        Color.clear
            .onGeometryChange(for: CalendarZoomTransitionState.Measurement?.self) { proxy in
                CalendarZoomFrames.measure(
                    anchors,
                    in: proxy,
                    mode: mode,
                    scrollOffset: scrollOffset,
                )
            } action: { value in
                zoom.updateMeasurement(value)
            }
            .onGeometryChange(for: Bool.self) { proxy in
                canReveal && proxy.size.width > 0 && proxy.size.height > 0
            } action: { isReady in
                if isReady {
                    onPresentationReady?()
                }
            }
            .allowsHitTesting(false)
    }
}

/// Moves fixed-layout copies of the visible tiles while the real scroll view stays positioned.
struct CalendarZoomOverlay<TileContent: View>: View {
    let phase: CalendarZoomTransitionState.Phase
    let content: (CalendarPresentationState.Target, CalendarPresentationState.Mode) -> TileContent
    let completion: (CalendarZoomTransitionState.ID) -> Void

    var body: some View {
        CalendarZoomFlight(phase: phase, content: content, completion: completion)
            .id(phase.source.id)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Calendar zoom") {
        NavigationStack {
            CalendarContentView(
                report: PreviewSupport.plannedStayYearReportModel(),
                initialMode: .overview,
            )
        }
        .whereBroadwayRoot()
    }
#endif
