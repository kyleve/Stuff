#if DEBUG
    import Darwin
    import Foundation

    /// A deterministic fatal condition exposed by the crash-reporting developer tool.
    enum DeveloperCrash: CaseIterable, Hashable, Identifiable {
        case swiftFatalError
        case arrayBounds
        case objectiveCException
        case abortSignal
        case invalidMemoryAccess

        var id: Self {
            self
        }

        var title: String {
            switch self {
                case .swiftFatalError:
                    String(localized: .developerCrashFatalErrorTitle)
                case .arrayBounds:
                    String(localized: .developerCrashArrayBoundsTitle)
                case .objectiveCException:
                    String(localized: .developerCrashObjectiveCExceptionTitle)
                case .abortSignal:
                    String(localized: .developerCrashAbortSignalTitle)
                case .invalidMemoryAccess:
                    String(localized: .developerCrashInvalidMemoryAccessTitle)
            }
        }

        var detail: String {
            switch self {
                case .swiftFatalError:
                    String(localized: .developerCrashFatalErrorDescription)
                case .arrayBounds:
                    String(localized: .developerCrashArrayBoundsDescription)
                case .objectiveCException:
                    String(localized: .developerCrashObjectiveCExceptionDescription)
                case .abortSignal:
                    String(localized: .developerCrashAbortSignalDescription)
                case .invalidMemoryAccess:
                    String(localized: .developerCrashInvalidMemoryAccessDescription)
            }
        }

        func trigger() -> Never {
            switch self {
                case .swiftFatalError:
                    fatalError("Developer-triggered fatalError crash")

                case .arrayBounds:
                    let values = [0]
                    _ = values[values.endIndex]
                    fatalError("Array bounds access unexpectedly returned")

                case .objectiveCException:
                    NSException(
                        name: .genericException,
                        reason: "Developer-triggered Objective-C exception",
                        userInfo: nil,
                    ).raise()
                    fatalError("Objective-C exception unexpectedly returned")

                case .abortSignal:
                    abort()

                case .invalidMemoryAccess:
                    guard let pointer = UnsafeMutableRawPointer(bitPattern: 0x1) else {
                        fatalError("Could not construct the invalid test pointer")
                    }
                    pointer.storeBytes(of: UInt8.zero, as: UInt8.self)
                    fatalError("Invalid memory access unexpectedly returned")
            }
        }
    }
#endif
