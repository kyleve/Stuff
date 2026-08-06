/// Selects a passport card's visual surface independently from whether device
/// motion has delivered a sample.
enum PassportCardSurfaceKind {
    case securityPrint
    case reflective(tilt: TiltProvider)

    var tilt: TiltProvider? {
        switch self {
            case .securityPrint: nil
            case let .reflective(tilt): tilt
        }
    }

    var isReflective: Bool {
        switch self {
            case .securityPrint: false
            case .reflective: true
        }
    }
}
