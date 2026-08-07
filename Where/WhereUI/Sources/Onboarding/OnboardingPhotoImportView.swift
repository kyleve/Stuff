import RegionKit
import SnapshotKit
import SwiftUI
import UIKit
import WhereCore

/// Optional onboarding step that scans only Photos metadata, previews a draft
/// timeline, and lets the user correct or exclude date ranges before import.
struct OnboardingPhotoImportView: View {
    @Bindable var model: OnboardingPhotoImportModel
    let onScan: () -> Void
    let onImport: () -> Void
    let onSkip: () -> Void

    @Environment(\.stylesheet) private var stylesheet
    @State private var editingStint: RegionStint?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: .onboardingPhotoNavigationTitle))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: .onboardingPhotoSkip), action: onSkip)
                            .disabled(isBusy)
                    }
                }
        }
        .sheet(item: $editingStint) { stint in
            PhotoHistoryStintEditor(
                stint: stint,
                onApply: model.apply,
            )
        }
        .alert(
            String(localized: .onboardingPhotoErrorTitle),
            isPresented: $model.isShowingError,
        ) {} message: {
            if let message = model.errorMessage { Text(message) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.activity {
            case .offer:
                offer
            case .scanning:
                AppIconLoadingView(caption: String(localized: .onboardingPhotoScanning))
            case .blocked:
                blocked
            case let .empty(limited):
                empty(isLimited: limited)
            case let .ready(draft, limited):
                review(draft: draft, isLimited: limited, isImporting: false)
            case let .importing(draft, limited):
                review(draft: draft, isLimited: limited, isImporting: true)
        }
    }

    private var offer: some View {
        VStack(spacing: stylesheet.spacing.xxxLarge) {
            Spacer(minLength: 0)
            Image(systemName: "photo.badge.location")
                .font(stylesheet.typography.onboardingIcon)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(spacing: stylesheet.spacing.large) {
                Text(String(localized: .onboardingPhotoTitle))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(String(localized: .onboardingPhotoDescription))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Label(
                    String(localized: .onboardingPhotoPrivacy),
                    systemImage: "lock.shield.fill",
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            Button(action: onScan) {
                Text(String(localized: .onboardingPhotoScan))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, stylesheet.spacing.xxxLarge)
        .padding(.bottom, stylesheet.spacing.xxxLarge)
    }

    private var blocked: some View {
        ContentUnavailableView {
            Label(
                String(localized: .onboardingPhotoAccessTitle),
                systemImage: "photo.badge.exclamationmark",
            )
        } description: {
            Text(String(localized: .onboardingPhotoAccessDescription))
        } actions: {
            Button(String(localized: .onboardingPhotoScan), action: onScan)
            Link(
                String(localized: .onboardingPhotoOpenSettings),
                destination: URL(string: UIApplication.openSettingsURLString)!,
            )
            .buttonStyle(.borderedProminent)
        }
    }

    private func empty(isLimited: Bool) -> some View {
        ContentUnavailableView {
            Label(
                String(localized: .onboardingPhotoEmptyTitle),
                systemImage: "calendar.badge.minus",
            )
        } description: {
            Text(String(localized: isLimited
                    ? .onboardingPhotoEmptyLimitedDescription
                    : .onboardingPhotoEmptyDescription))
        } actions: {
            if isLimited {
                Button(String(localized: .onboardingPhotoScan), action: onScan)
                Link(
                    String(localized: .onboardingPhotoOpenSettings),
                    destination: URL(string: UIApplication.openSettingsURLString)!,
                )
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func review(
        draft: PhotoHistoryDraft,
        isLimited: Bool,
        isImporting: Bool,
    ) -> some View {
        let stints = PresenceTimeline.stints(from: draft.report, calendar: draft.calendar)
        return VStack(spacing: 0) {
            if isLimited {
                Label(
                    String(localized: .onboardingPhotoLimitedNotice),
                    systemImage: "photo.on.rectangle.angled",
                )
                .font(.subheadline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.15))
            }
            List {
                Section {
                    ForEach(stints) { stint in
                        Button { editingStint = stint } label: {
                            PhotoHistoryStintRow(stint: stint, calendar: draft.calendar)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(String(localized: .onboardingPhotoReviewTitle))
                } footer: {
                    Text(String(localized: .onboardingPhotoReviewFooter))
                }

                if draft.hasExcludedDays {
                    Section {
                        Button(
                            String(localized: .onboardingPhotoRestoreExcluded),
                            action: model.restoreExcludedDays,
                        )
                    } footer: {
                        Text(String(localized: .onboardingPhotoRestoreExcludedFooter))
                    }
                }

                Section {
                    Button(action: onImport) {
                        if isImporting {
                            SavingStatusRow(text: String(localized: .onboardingPhotoImporting))
                        } else {
                            Text(String(localized: .onboardingPhotoImport))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isImporting || stints.isEmpty)
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    private var isBusy: Bool {
        switch model.activity {
            case .scanning, .importing: true
            case .offer, .blocked, .empty, .ready: false
        }
    }
}

#if DEBUG
    extension OnboardingPhotoImportView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            [
                whereSnapshot(name: "Offer", configurations: .screenDefaults) {
                    OnboardingPhotoImportView(
                        model: OnboardingPhotoImportModel(),
                        onScan: {},
                        onImport: {},
                        onSkip: {},
                    )
                },
                whereSnapshot(name: "Review", configurations: .screenDefaults) {
                    let model = OnboardingPhotoImportModel()
                    model.activity = .ready(Self.previewDraft, isLimited: true)
                    return OnboardingPhotoImportView(
                        model: model,
                        onScan: {},
                        onImport: {},
                        onSkip: {},
                    )
                },
            ]
        }

        private static var previewDraft: PhotoHistoryDraft {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            return PhotoHistoryDraft(
                year: 2026,
                calendar: calendar,
                samples: [
                    LocationSample(
                        timestamp: Date(timeIntervalSince1970: 1_768_500_000),
                        coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                        horizontalAccuracy: 12,
                        source: .photo,
                    ),
                    LocationSample(
                        timestamp: Date(timeIntervalSince1970: 1_768_586_400),
                        coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                        horizontalAccuracy: 15,
                        source: .photo,
                    ),
                ],
                regions: [.california, .newYork],
            )
        }
    }
#endif

/// Compact, tappable preview row for one provisional stay.
private struct PhotoHistoryStintRow: View {
    let stint: RegionStint
    let calendar: Calendar

    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(stint.region.localizedName)
                    .foregroundStyle(.primary)
                Text(dateRange)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Text(regionStyles.style(for: stint.region).emoji)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityHint(String(localized: .onboardingPhotoEditHint))
    }

    private var dateRange: String {
        DateRangeFormatting.abbreviated(
            start: stint.start,
            end: stint.end,
            calendar: calendar,
        )
    }
}

/// Edits all or part of one provisional stay without touching persistence.
private struct PhotoHistoryStintEditor: View {
    let stint: RegionStint
    let onApply: (PhotoHistoryDraft.DayDecision, Date, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var regions: RegionSelectionState

    init(
        stint: RegionStint,
        onApply: @escaping (PhotoHistoryDraft.DayDecision, Date, Date) -> Void,
    ) {
        self.stint = stint
        self.onApply = onApply
        _start = State(initialValue: stint.start)
        _end = State(initialValue: stint.end)
        _regions = State(initialValue: RegionSelectionState(selectedRegions: [stint.region]))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WhereDatePicker(
                        String(localized: .onboardingPhotoFrom),
                        selection: $start,
                        earliest: stint.start,
                        latest: end,
                        displayedComponents: .date,
                    )
                    WhereDatePicker(
                        String(localized: .onboardingPhotoThrough),
                        selection: $end,
                        earliest: start,
                        latest: stint.end,
                        displayedComponents: .date,
                    )
                } footer: {
                    Text(String(localized: .onboardingPhotoRangeFooter))
                }

                Section {
                    ForEach(regions.items) { RegionToggleRow(item: $0) }
                } header: {
                    Text(String(localized: .relabelRegionsHeader))
                }

                Section {
                    Button(String(localized: .onboardingPhotoUseLocations)) {
                        onApply(.included, start, end)
                        dismiss()
                    }

                    Button(String(localized: .onboardingPhotoExclude), role: .destructive) {
                        onApply(.excluded, start, end)
                        dismiss()
                    }
                } footer: {
                    Text(String(localized: .onboardingPhotoExcludeFooter))
                }
            }
            .navigationTitle(String(localized: .onboardingPhotoEditTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .commonCancel)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: .manualSave)) {
                        onApply(.corrected(regions.selectedRegions), start, end)
                        dismiss()
                    }
                    .disabled(regions.selectedRegions.isEmpty)
                }
            }
        }
    }
}
