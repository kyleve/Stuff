import ThrowCore

actor LocationFixAccumulator {
    private var best: LocationFix?
    private var headingHint: Bearing?

    func consider(_ fix: LocationFix) {
        let currentAccuracy = best?.horizontalAccuracyMeters ?? .infinity
        guard fix.horizontalAccuracyMeters < currentAccuracy else {
            return
        }
        best = fix
    }

    func record(_ heading: Bearing) {
        headingHint = heading
    }

    func result() -> (fix: LocationFix?, heading: Bearing?) {
        (best, headingHint)
    }
}
