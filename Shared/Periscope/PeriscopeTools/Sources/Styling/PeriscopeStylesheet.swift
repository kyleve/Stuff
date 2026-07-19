import BroadwayCore
import BroadwayUI
import CoreGraphics
import PeriscopeCore
import SwiftUI

/// PeriscopeTools' design tokens, resolved as a Broadway ``BStylesheet``.
///
/// The former inline fonts, spacing, and severity/exit colors scattered across
/// the row, badge, detail, and span views now live here as one token set. Most
/// tokens are fixed; a slice derives from the ``BContext`` traits handed to
/// `init(context:)` (roomier rows at accessibility Dynamic Type sizes). Views
/// read the active tokens from the environment via `@Environment(\.stylesheet)`
/// (seeded by ``SwiftUI/View/periscopeBroadwayRoot()`` on each public tool
/// view); code off the `View` tree (tests) uses ``default``.
struct PeriscopeStylesheet: BStylesheet {
    var spacing = Spacing()
    var row = RowStyles.standard
    var badge = BadgeStyle.standard
    var typography = Typography.standard
    var palette = Palette.standard

    init() {}

    init(context: SlicingContext) throws {
        // Start from the fixed scale (property defaults), then adjust only the
        // trait-reactive slice, so a default/system context reproduces `default`.
        let traits = context.traits

        // Give the (already tight) rows a little more breathing room at
        // accessibility Dynamic Type sizes, where truncation bites hardest.
        if traits.contentSizeCategory.isAccessibilitySize {
            row.comfortable.messageLineLimit = 4
            row.compact.messageLineLimit = 2
        }
    }

    /// The fixed token set: the fallback used off the `View` tree (tests) and
    /// when no Broadway root has seeded a context.
    static let `default` = PeriscopeStylesheet()
}

// MARK: - Spacing

extension PeriscopeStylesheet {
    /// Generic spacing scale, in points, for tool chrome that isn't part of a
    /// component's own style group.
    struct Spacing: Equatable {
        var xSmall: CGFloat = 4
        var small: CGFloat = 6
        var medium: CGFloat = 8
    }
}

// MARK: - Rows

extension PeriscopeStylesheet {
    /// How tightly the shared event row packs its lines. Persisted as a user
    /// preference (see ``LogRowDensity``) and resolved to a ``RowStyle`` via
    /// ``RowStyles``' subscript, so callers read one spec instead of branching.
    enum Density: String, CaseIterable, Hashable {
        case comfortable
        case compact

        /// Capitalized label for the density picker.
        var displayName: String {
            rawValue.capitalized
        }

        /// UserDefaults key backing the viewer's persisted density preference.
        static let defaultsKey = "periscope.tools.rowDensity"

        /// The persisted preference, defaulting to ``compact`` so the tooling
        /// reads dense out of the box (the roomier ``comfortable`` is the raw
        /// environment fallback for rootless contexts — previews, isolated
        /// rows — not the seeded surfaces).
        static func load(from defaults: UserDefaults) -> Self {
            defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .compact
        }

        /// Persist this density as the preference.
        func save(to defaults: UserDefaults) {
            defaults.set(rawValue, forKey: Self.defaultsKey)
        }
    }

    /// The one-line event summary's geometry and truncation, for one density.
    struct RowStyle: Equatable {
        /// Padding above and below each row.
        var verticalPadding: CGFloat
        /// Vertical spacing between the header, message, and scope-path lines.
        var lineSpacing: CGFloat
        /// Horizontal spacing within the header (badges, name, timestamp).
        var headerSpacing: CGFloat
        /// Message truncation limit.
        var messageLineLimit: Int
        /// Indentation applied per scope-tree depth level when a row renders
        /// inside a hierarchy (0 in the flat list).
        var indentStep: CGFloat
    }

    /// The row style per density, with a subscript that resolves one spec.
    struct RowStyles: Equatable {
        var comfortable: RowStyle
        var compact: RowStyle

        subscript(_ density: Density) -> RowStyle {
            switch density {
                case .comfortable: comfortable
                case .compact: compact
            }
        }

        static let standard = RowStyles(
            comfortable: RowStyle(
                verticalPadding: 2,
                lineSpacing: 4,
                headerSpacing: 8,
                messageLineLimit: 3,
                indentStep: 14,
            ),
            compact: RowStyle(
                verticalPadding: 1,
                lineSpacing: 1,
                headerSpacing: 6,
                messageLineLimit: 1,
                indentStep: 12,
            ),
        )
    }
}

// MARK: - Badges

extension PeriscopeStylesheet {
    /// The capsule level/exit chips shared by the row and detail views.
    struct BadgeStyle: Equatable {
        var font: Font = .caption2.weight(.semibold)
        var horizontalPadding: CGFloat = 6
        var verticalPadding: CGFloat = 2
        /// Opacity of the tinted capsule fill behind the (full-tint) label.
        var backgroundOpacity: Double = 0.18
        /// Diameter padding of the inspect-mode overlay badge.
        var inspectPadding: CGFloat = 4

        static let standard = BadgeStyle()
    }
}

// MARK: - Typography

extension PeriscopeStylesheet {
    /// The tool's display faces, named by role rather than by size so a retune
    /// happens in one place.
    struct Typography: Equatable {
        var eventName: Font = .caption
        var message: Font = .callout
        var scopePath: Font = .caption2
        var timestamp: Font = .caption2
        var payload: Font = .caption.monospaced()
        var spanName: Font = .callout.weight(.medium)
        var spanAge: Font = .caption
        var spanDetail: Font = .caption2

        static let standard = Typography()
    }
}

// MARK: - Palette

extension PeriscopeStylesheet {
    /// The tool's semantic colors: severity band tints, span-exit chip tints,
    /// and the inspect-mode badge. Kept here (not inline on `LogLevel` /
    /// `SpanExit.Mode`) so the whole color language is themeable from one place.
    struct Palette: Equatable {
        // Severity bands, ascending. A custom level inherits the color of the
        // band its severity falls into.
        var levelDebug: Color = .gray
        var levelInfo: Color = .blue
        var levelNotice: Color = .teal
        var levelWarning: Color = .yellow
        var levelError: Color = .orange
        var levelFault: Color = .red

        // Span-exit chips: calm for expected outcomes, hot for the ones worth
        // chasing.
        var spanSuccess: Color = .green
        var spanCancelled: Color = .gray
        var spanSuperseded: Color = .yellow
        var spanExpired: Color = .orange
        var spanFailure: Color = .red
        var spanOrphaned: Color = .purple

        /// The inspect-mode overlay badge.
        var inspectBadge: Color = .purple

        static let standard = Palette()

        /// Tint escalating with severity — banded so custom levels inherit a
        /// sensible color from their position in the ladder.
        func tint(forLevel level: LogLevel) -> Color {
            switch level.severity {
                case ..<LogLevel.info.severity: levelDebug
                case ..<LogLevel.notice.severity: levelInfo
                case ..<LogLevel.warning.severity: levelNotice
                case ..<LogLevel.error.severity: levelWarning
                case ..<LogLevel.fault.severity: levelError
                default: levelFault
            }
        }

        /// Chip tint for a span's exit mode.
        func tint(forSpanExit mode: SpanExit.Mode) -> Color {
            switch mode {
                case .success: spanSuccess
                case .cancelled: spanCancelled
                case .superseded: spanSuperseded
                case .expired: spanExpired
                case .failure: spanFailure
                case .orphaned: spanOrphaned
            }
        }
    }
}

// MARK: - Themes

/// PeriscopeTools' Broadway themes, seeded at each tool root by
/// ``SwiftUI/View/periscopeBroadwayRoot()``. Empty for now — the sheet derives
/// from traits, not themes — and the seam a future palette theme would use.
enum PeriscopeThemes {
    static var current: BThemes {
        BThemes()
    }
}

// MARK: - Root

extension View {
    /// Seeds PeriscopeTools' Broadway context — live system traits plus
    /// ``PeriscopeThemes`` — so descendants resolve `@Environment(\.stylesheet)`
    /// against real traits rather than ``PeriscopeStylesheet/default``.
    ///
    /// Applied on each public tool view (the viewer, tracer, inspector sheet,
    /// open-spans view) so the tooling styles correctly whether or not the host
    /// app has its own Broadway root; nesting under an app root simply re-seeds
    /// from the same system traits.
    func periscopeBroadwayRoot() -> some View {
        broadwayRoot(themes: PeriscopeThemes.current)
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// The active PeriscopeTools tokens, resolved from the Broadway `BContext`
    /// seeded by ``SwiftUI/View/periscopeBroadwayRoot()``. With no root present
    /// (e.g. an inspect badge on a host view, isolated previews) resolution
    /// falls back to ``PeriscopeStylesheet/default``. A resolution failure is a
    /// programmer error (the initializer never throws), so it traps in debug and
    /// falls back to `default` in release.
    var stylesheet: PeriscopeStylesheet {
        bContext.stylesheet(PeriscopeStylesheet.self, fallback: .default)
    }

    /// The row density for the event list, read by ``LogEventRow`` to pick a
    /// ``PeriscopeStylesheet/RowStyle``. Seeded by the viewer from a persisted
    /// preference; defaults to comfortable everywhere else.
    @Entry var logRowDensity: PeriscopeStylesheet.Density = .comfortable
}
