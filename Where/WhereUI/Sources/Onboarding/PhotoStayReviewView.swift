import RegionKit
import SnapshotKit
import SwiftUI
@_spi(Testing) import WhereCore

@Observable @MainActor
final class PhotoStayReviewModel {
    var draft: PhotoStayDraft
    let selection: PrimaryRegionSelectionModel

    init(draft: PhotoStayDraft, selection: PrimaryRegionSelectionModel) {
        self.draft = draft
        self.selection = selection
    }

    func preparePicker() {
        selection.suggestRegions(from: draft.report.totals)
    }
}

struct PhotoStayReviewView: View {
    let model: PhotoStayReviewModel
    let onContinue: () -> Void
    @State private var editing: EditSelection?
    private var calendar: Calendar {
        model.draft.scan.calendar
    }

    private struct EditSelection: Identifiable {
        let original: PhotoStay?
        let id = UUID()
    }

    var body: some View {
        NavigationStack {
            List {
                if model.draft.scan.access == .limited { Text(.photoReviewLimited) }
                Section {
                    ForEach(PresenceTimeline.stints(
                        from: model.draft.report,
                        calendar: calendar,
                    )) { stint in
                        let stay = PhotoStay(
                            region: stint.region,
                            start: CalendarDay(from: stint.start, in: calendar),
                            end: CalendarDay(from: stint.end, in: calendar),
                        )
                        let count = model.draft.observedDayCount(in: stay)
                        Button { editing = EditSelection(original: stay) } label: {
                            VStack(alignment: .leading) {
                                Text(stay.region.localizedName).font(.headline)
                                Text(DateRangeFormatting.abbreviated(
                                    start: stay.start,
                                    end: stay.end,
                                    calendar: calendar,
                                ))
                                LabeledContent { Text(WhereFormat.dayCount(count)) } label: {
                                    Text(.photoReviewObserved)
                                }
                                let added = stay.start.days(through: stay.end).count - count
                                if added > 0 {
                                    LabeledContent { Text(WhereFormat.dayCount(added)) } label: {
                                        Text(.photoReviewConfirmed)
                                    }
                                }
                            }
                        }
                    }
                    if model.draft.report.days.isEmpty { Text(.photoReviewEmpty) }
                    Button { editing = EditSelection(original: nil) } label: {
                        Text(.photoReviewAdd)
                    }
                } header: { Text(.photoReviewStays) } footer: { Text(.photoReviewNote) }
                if !model.draft.pendingGaps.isEmpty {
                    Section {
                        ForEach(model.draft.pendingGaps) { gap in
                            VStack(alignment: .leading) {
                                Text(gap.region.localizedName).font(.headline)
                                let range = DateRangeFormatting.abbreviated(
                                    start: gap.start,
                                    end: gap.end,
                                    calendar: calendar,
                                )
                                Text(range)
                                Text(WhereFormat.dayCount(gap.start.days(through: gap.end).count))
                                Button { model.draft.decide(gap, include: true) } label: {
                                    Text(.photoReviewConfirm)
                                }.accessibilityValue("\(gap.region.localizedName), \(range)")
                                Button { model.draft.decide(gap, include: false) } label: {
                                    Text(.photoReviewDecline)
                                }.accessibilityValue("\(gap.region.localizedName), \(range)")
                            }
                            .buttonStyle(.borderless)
                        }
                    } header: { Text(.photoReviewGaps) } footer: { Text(.photoReviewGapFooter) }
                }
                if !model.draft.confirmedGaps.isEmpty {
                    Section {
                        ForEach(model.draft.confirmedGaps) { gap in
                            LabeledContent(
                                gap.region.localizedName,
                                value: DateRangeFormatting.abbreviated(
                                    start: gap.start,
                                    end: gap.end,
                                    calendar: calendar,
                                ),
                            )
                        }
                    } header: { Text(.photoReviewConfirmed) }
                }
                Button { model.preparePicker(); onContinue() } label: { Text(.photoReviewContinue) }
            }
            .whereFormRoot()
            .navigationTitle(Text(.photoReviewTitle))
        }
        .sheet(item: $editing) { selected in
            PhotoStayEditor(model: model, original: selected.original)
        }
    }
}

private struct PhotoStayEditor: View {
    let model: PhotoStayReviewModel
    let original: PhotoStay?
    @Environment(\.dismiss) private var dismiss
    @State private var region: Region
    @State private var from: Date
    @State private var through: Date

    init(model: PhotoStayReviewModel, original: PhotoStay?) {
        self.model = model
        self.original = original
        let scan = model.draft.scan
        _region = State(initialValue: original?.region ?? .other)
        _from = State(initialValue: (original?.start ?? scan.through).startOfDay(in: scan.calendar))
        _through = State(initialValue: (original?.end ?? scan.through)
            .startOfDay(in: scan.calendar))
    }

    var body: some View {
        let calendar = model.draft.scan.calendar
        let first = model.draft.bounds.lowerBound.startOfDay(in: calendar)
        let last = model.draft.bounds.upperBound.startOfDay(in: calendar)
        NavigationStack {
            Form {
                Picker(selection: $region) {
                    ForEach(Region.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                } label: { Text(.photoReviewRegion) }
                WhereDatePicker(
                    String(localized: .manualFrom),
                    selection: $from,
                    earliest: first,
                    latest: last,
                    displayedComponents: .date,
                )
                WhereDatePicker(
                    String(localized: .manualThrough),
                    selection: $through,
                    earliest: from,
                    latest: last,
                    displayedComponents: .date,
                )
                if let original {
                    Button(role: .destructive) {
                        model.draft.edit(original, to: nil)
                        dismiss()
                    } label: { Text(.photoReviewRemove) }
                }
            }
            .whereFormRoot()
            .navigationTitle(Text(original == nil ? .photoReviewAdd : .photoReviewEdit))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(.commonCancel) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let changed = PhotoStay(
                            region: region,
                            start: CalendarDay(from: from, in: calendar),
                            end: CalendarDay(from: through, in: calendar),
                        )
                        if model.draft.edit(original, to: changed) { dismiss() }
                    } label: { Text(.commonSave) }
                        .disabled(through < from)
                }
            }
        }
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
        .onChange(of: from) { _, start in if through < start { through = start } }
    }
}

#if DEBUG
    extension PhotoStayReviewView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            let calendar = Calendar(identifier: .gregorian)
            let points: [DatedPhotoLocation] = [2, 6].compactMap { index in
                let day = CalendarDay(year: 2026, month: 6, day: index)
                let time = day.startOfDay(in: calendar)
                guard let observation = PhotoObservation(
                    capturedAt: time,
                    addedAt: time,
                    coordinate: Coordinate(
                        latitude: 43.65,
                        longitude: -79.38,
                    ),
                    accuracy: 10,
                ),
                    let region = Region(rawValue: "ca-ON") else { return nil }
                return DatedPhotoLocation(observation: observation, day: day, region: region)
            }
            return ["Gap", "Corrected", "Suggestions"].map { state in whereSnapshot(
                name: state,
                configurations: [
                    .init(device: .iPhone),
                    .init(device: .iPad),
                    .init(
                        dynamicType: .accessibility5,
                        device: .iPhone,
                    ),
                ],
                measurementReadiness: .immediate,
            ) {
                let scan = PhotoLocationScan(
                    calendar: calendar,
                    through: CalendarDay(year: 2026, month: 6, day: 6),
                    access: .limited,
                    points: points,
                )
                let review = PhotoStayReviewModel(
                    draft: PhotoStayDraft(scan: scan),
                    selection: .init(),
                )
                if state != "Gap", let gap = review.draft.pendingGaps.first {
                    review.draft.decide(gap, include: true)
                    review.preparePicker()
                }
                return Group {
                    if state == "Suggestions" {
                        NavigationStack { RegionPickerView(model: review.selection) }
                    } else {
                        PhotoStayReviewView(model: review, onContinue: {})
                    }
                }
            } }
        }
    }

    #Preview { PhotoStayReviewView.snapshotPreviews }
#endif
