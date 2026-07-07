import SwiftUI

/// Inline "work in progress" row for manual-day forms. Shown while a save is
/// in flight so the up-to-a-few-seconds one-shot GPS capture (see
/// `LocationSource.requestCurrentLocation()`) has visible feedback rather than
/// leaving the user on a silently disabled Save button.
struct SavingStatusRow: View {
    let text: String

    var body: some View {
        HStack(spacing: UIConstants.Spacings.small) {
            ProgressView()
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    #Preview {
        Form {
            Section {
                SavingStatusRow(text: "Capturing location…")
            }
        }
    }
#endif
