enum DashboardDestination: Hashable {
    case settings
    case calibration
    #if DEBUG
        case projectorLab
    #endif
}
