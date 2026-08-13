import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

/// Planning controls shared by focused and multi-region forecast cards.
struct LocationForecastControls: View {
    private enum ClearState: Equatable {
        case idle
        case clearing
        case failed(String)
    }

    let editableRegions: [Region]
    var plannedStay: PlannedStay?
    let editAction: (Region) -> Void
    var clearAction: (@MainActor () async throws -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var clearState: ClearState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 8))

            layout {
                if editableRegions.count == 1, let region = editableRegions.first {
                    Button(
                        String(localized: .locationForecastEditStay),
                        systemSymbol: .calendarBadgeClock,
                    ) {
                        editAction(region)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Menu {
                        ForEach(editableRegions, id: \.self) { region in
                            Button(region.localizedName) {
                                editAction(region)
                            }
                        }
                    } label: {
                        Label(
                            String(localized: .locationForecastEditStay),
                            systemSymbol: .calendarBadgeClock,
                        )
                    }
                    .buttonStyle(.bordered)
                }

                if let plannedStay,
                   editableRegions.contains(plannedStay.region),
                   clearAction != nil
                {
                    if clearState == .clearing {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(String(localized: .locationForecastClearingStay))
                    } else {
                        Button(
                            String(localized: .locationForecastClearStay),
                            role: .destructive,
                            action: clear,
                        )
                        .buttonStyle(.bordered)
                    }
                }
            }

            if case let .failed(message) = clearState {
                Label(message, systemSymbol: .exclamationmarkTriangleFill)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func clear() {
        guard let clearAction else { return }
        clearState = .clearing
        Task {
            do {
                try await clearAction()
                clearState = .idle
            } catch {
                clearState = .failed(error.localizedDescription)
            }
        }
    }
}

#if DEBUG
    #Preview {
        LocationForecastControls(
            editableRegions: [.california, .newYork],
            plannedStay: PlannedStay(
                region: .newYork,
                through: CalendarDay(year: 2026, month: 8, day: 15),
            ),
            editAction: { _ in },
            clearAction: {},
        )
        .padding()
    }
#endif
