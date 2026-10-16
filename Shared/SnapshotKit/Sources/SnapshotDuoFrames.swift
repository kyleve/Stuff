import CoreGraphics

extension SnapshotConfiguration.Frame {
    /// Duo outer portrait bounds and insets measured on the pinned simulator.
    /// These synthetic viewports do not change the host simulator's physical pose.
    /// See `Documentation/DuoMeasurements.json` for the native measurements.
    public static let duoOuterPortrait = viewport(
        name: "duoOuterPortrait",
        size: CGSize(width: 466, height: 678),
        safeAreaInsets: Insets(top: 0, leading: 0, bottom: 34, trailing: 84),
        layoutTraits: .phonePortrait,
    )

    /// Duo outer landscape, with compact height and a trailing system bar.
    public static let duoOuterLandscape = viewport(
        name: "duoOuterLandscape",
        size: CGSize(width: 678, height: 466),
        safeAreaInsets: Insets(top: 0, leading: 0, bottom: 34, trailing: 84),
        layoutTraits: LayoutTraits(
            horizontalSizeClass: .compact,
            verticalSizeClass: .compact,
            interfaceIdiom: .phone,
        ),
    )

    /// Duo inner portrait retains the phone idiom with regular size classes.
    public static let duoInnerPortrait = viewport(
        name: "duoInnerPortrait",
        size: CGSize(width: 669, height: 951),
        safeAreaInsets: Insets(top: 82, leading: 0, bottom: 34, trailing: 0),
        layoutTraits: LayoutTraits(
            horizontalSizeClass: .regular,
            verticalSizeClass: .regular,
            interfaceIdiom: .phone,
        ),
    )

    /// Duo inner landscape uses regular size classes and a trailing system bar.
    public static let duoInnerLandscape = viewport(
        name: "duoInnerLandscape",
        size: CGSize(width: 951, height: 669),
        safeAreaInsets: Insets(top: 0, leading: 0, bottom: 34, trailing: 84),
        layoutTraits: LayoutTraits(
            horizontalSizeClass: .regular,
            verticalSizeClass: .regular,
            interfaceIdiom: .phone,
        ),
    )
}
