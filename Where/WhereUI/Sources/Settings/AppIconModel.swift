import Observation
import UIKit

/// Drives the app-icon picker: the list of options (from `AppIcons.json`), the
/// currently-selected one, and applying a new choice through the
/// `AlternateIconSetting` seam.
///
/// The live icon is the source of truth — `selectedID` is derived from
/// `UIApplication.alternateIconName` at init (iOS persists it across launches),
/// so there's no separate `WherePreferences` key to drift from reality.
@MainActor
@Observable
final class AppIconModel {
    let options: [AppIconOption]
    private(set) var selectedID: AppIconID

    /// Set when applying an icon fails; surfaced as an alert and cleared via
    /// `isShowingError`.
    var applyError: String?

    private let setter: any AlternateIconSetting

    init(
        options: [AppIconOption]? = nil,
        setter: any AlternateIconSetting = UIApplication.shared,
    ) {
        let resolved = options ?? AppIconModel.loadOptions()
        self.options = resolved
        self.setter = setter
        selectedID = AppIconModel.matchSelection(in: resolved, current: setter.alternateIconName)
    }

    /// Whether the device supports alternate icons at all (false is rare on
    /// iOS, but the picker hides the Change affordance when it happens).
    var supportsAlternateIcons: Bool {
        setter.supportsAlternateIcons
    }

    var selectedOption: AppIconOption? {
        options.first { $0.id == selectedID }
    }

    func isSelected(_ option: AppIconOption) -> Bool {
        option.id == selectedID
    }

    /// Apply `option` as the app's icon. A no-op when it's already selected;
    /// failures land in `applyError` rather than throwing to the view. Returns
    /// `true` when the icon actually changed, so the caller can decide whether
    /// to dismiss (and leave the picker up to show the error otherwise).
    @discardableResult
    func apply(_ option: AppIconOption) async -> Bool {
        guard option.id != selectedID, supportsAlternateIcons else { return false }
        do {
            try await setter.setAlternateIconName(option.alternateIconName)
            selectedID = option.id
            return true
        } catch {
            applyError = error.localizedDescription
            return false
        }
    }

    /// `.alert(isPresented:)` binding — computed get/set over `applyError` so
    /// the error string stays the single source of truth (repo convention; no
    /// closure `Binding`).
    var isShowingError: Bool {
        get { applyError != nil }
        set { if !newValue { applyError = nil } }
    }

    private static func loadOptions() -> [AppIconOption] {
        (try? AppIconCatalog.load()) ?? []
    }

    /// Match the live `alternateIconName` to a manifest option, falling back to
    /// the primary (or first) option when the active icon isn't listed — e.g.
    /// it was removed from the manifest since it was last set.
    private static func matchSelection(
        in options: [AppIconOption],
        current alternateIconName: String?,
    ) -> AppIconID {
        AppIconCatalog.selectedOption(in: options, current: alternateIconName)?.id ?? AppIconID("")
    }
}

#if DEBUG
    extension AppIconModel {
        /// A model wired to an in-memory icon setter so previews and the
        /// canvas never touch the springboard.
        static func preview(activeAlternateIconName: String? = nil) -> AppIconModel {
            AppIconModel(
                setter: InMemoryAlternateIconSetting(alternateIconName: activeAlternateIconName),
            )
        }
    }

    extension AppIconCatalog {
        /// Test/preview helper: whether `name` resolves to a real imageset in
        /// WhereUI's resource bundle (`.module` here is WhereUI's, which is the
        /// bundle the picker renders previews from).
        static func previewImageExists(named name: String) -> Bool {
            UIImage(named: name, in: .module, compatibleWith: nil) != nil
        }
    }

    /// Records the requested icon instead of calling the real API, for previews
    /// and hosted smoke tests.
    @MainActor
    final class InMemoryAlternateIconSetting: AlternateIconSetting {
        var supportsAlternateIcons: Bool
        private(set) var alternateIconName: String?

        init(supportsAlternateIcons: Bool = true, alternateIconName: String? = nil) {
            self.supportsAlternateIcons = supportsAlternateIcons
            self.alternateIconName = alternateIconName
        }

        func setAlternateIconName(_ alternateIconName: String?) async throws {
            self.alternateIconName = alternateIconName
        }
    }
#endif
