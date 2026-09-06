import ThrowCore

enum LocationResolution {
    case target(LocationFix)
    case timedOut
    case failed
}
