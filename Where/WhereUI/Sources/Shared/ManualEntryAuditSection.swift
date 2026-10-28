import SwiftUI
import WhereCore

/// Read-only audit trail for a manual day entry — when it was made, its note,
/// and the device's location at the time. Shared by the relabel and logged-day
/// editors so a residency review can see who asserted a day and why.
struct ManualEntryAuditSection: View {
    let audit: ManualEntryAudit

    var body: some View {
        Section {
            LabeledContent(
                String(localized: .auditRecordedAt),
                value: recordedAtText(audit.recordedAt),
            )
            if let note = audit.note {
                LabeledContent(String(localized: .auditNote), value: note)
            }
            LabeledContent(String(localized: .auditLocation), value: locationText(audit.location))
        } header: {
            Text(String(localized: .auditHeader))
        }
    }

    private func recordedAtText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
    }

    private func locationText(_ location: CapturedLocation?) -> String {
        guard let location else { return String(localized: .auditLocationUnavailable) }
        return WhereFormat.auditCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
        )
    }
}

#if DEBUG
    import RegionKit

    #Preview {
        Form {
            ManualEntryAuditSection(audit: ManualEntryAudit(
                recordedAt: .now,
                note: "Corrected after reviewing my boarding pass.",
                location: CapturedLocation(
                    coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                    horizontalAccuracy: 12,
                    timestamp: .now,
                ),
            ))
        }
    }
#endif
