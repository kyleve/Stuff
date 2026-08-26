import Foundation
import SwiftUI
import ThrowCore

struct ReadyStepView: View {
    let model: OnboardingFlowModel

    var body: some View {
        Form {
            Section(String(localized: .dashboardSource)) {
                LabeledContent(String(localized: .dashboardSource), value: sourceName)
                if model.sourceChoice == .readsb {
                    LabeledContent(String(localized: .sourceLocalURL)) {
                        Text(verbatim: model.readsbURL)
                            .lineLimit(2)
                    }
                }
                if model.sourceChoice == .adsbExchange || model.sourceChoice == .flightradar24 {
                    LabeledContent(String(localized: .sourceCredential)) {
                        Text(verbatim: credentialName)
                            .privacySensitive()
                    }
                    LabeledContent(String(localized: .sourceInterval)) {
                        Text(
                            Duration.seconds(Int(model.pollingIntervalSeconds)),
                            format: .time(pattern: .minuteSecond),
                        )
                    }
                    LabeledContent(String(localized: .sourceRequestsPerHour)) {
                        Text(
                            model.usageEstimate.displayedRequestsPerHour,
                            format: .number,
                        )
                    }
                    LabeledContent(String(localized: .sourceRequests30Days)) {
                        Text(
                            model.usageEstimate.displayedThirtyDayUpperBound,
                            format: .number,
                        )
                    }
                }
            }

            Section(String(localized: .dashboardLocation)) {
                LabeledContent(String(localized: .settingsLocation), value: locationModeName)
                LabeledContent(String(localized: .onboardingReadyCoordinate)) {
                    Text(verbatim: coordinateName)
                }
                LabeledContent(String(localized: .locationAltitude)) {
                    Text(
                        Measurement(value: model.observerAltitudeFeet, unit: UnitLength.feet),
                        format: .measurement(
                            width: .abbreviated,
                            usage: .asProvided,
                            numberFormatStyle: .number.precision(.fractionLength(0)),
                        ),
                    )
                }
                LocationHealthRow(health: model.locationHealth)
            }

            Section(String(localized: .settingsMode)) {
                LabeledContent(String(localized: .settingsMode), value: modeName)
                switch model.selectedMode {
                    case .map:
                        LabeledContent(String(localized: .viewportMapRadius)) {
                            Text(
                                Measurement(
                                    value: model.mapRadius,
                                    unit: UnitLength.nauticalMiles,
                                ),
                                format: .measurement(
                                    width: .abbreviated,
                                    usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0)),
                                ),
                            )
                        }
                    case .trueSky:
                        LabeledContent(String(localized: .viewportMinimumElevation)) {
                            Text(
                                Measurement(
                                    value: model.minimumElevation,
                                    unit: UnitAngle.degrees,
                                ),
                                format: .measurement(
                                    width: .abbreviated,
                                    usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0)),
                                ),
                            )
                        }
                    case nil:
                        EmptyView()
                }
            }

            Section(String(localized: .calibrationTitle)) {
                LabeledContent(String(localized: .dashboardOutput), value: outputName)
                LabeledContent(String(localized: .calibrationBearing)) {
                    Text(
                        Measurement(value: model.screenTopBearing, unit: UnitAngle.degrees),
                        format: .measurement(
                            width: .abbreviated,
                            usage: .asProvided,
                            numberFormatStyle: .number.precision(.fractionLength(0 ... 1)),
                        ),
                    )
                }
                LabeledContent(String(localized: .calibrationRotation)) {
                    Text(
                        Measurement(
                            value: Double(model.rotation.rawValue),
                            unit: UnitAngle.degrees,
                        ),
                        format: .measurement(width: .abbreviated, usage: .asProvided),
                    )
                }
                LabeledContent(String(localized: .calibrationInset)) {
                    Text(model.safeInsetPercent / 100, format: .percent)
                }
                LabeledContent(
                    String(localized: .calibrationFlipHorizontal),
                    value: model.flipsHorizontally
                        ? String(localized: .commonOn)
                        : String(localized: .commonOff),
                )
                LabeledContent(
                    String(localized: .calibrationFlipVertical),
                    value: model.flipsVertically
                        ? String(localized: .commonOn)
                        : String(localized: .commonOff),
                )
                LabeledContent(
                    String(localized: .calibrationVerified),
                    value: calibrationStatusName,
                )
            }

            Section {
                LabeledContent(
                    String(localized: .settingsLabels),
                    value: String(localized: .labelsAdaptive),
                )
                LabeledContent(
                    String(localized: .settingsLayers),
                    value: layerSummary,
                )
                LabeledContent(
                    String(localized: .settingsGroundAircraft),
                    value: String(localized: .commonOff),
                )
                LabeledContent(String(localized: .settingsQuiet), value: quietName)
                if model.quietEnabled {
                    LabeledContent(String(localized: .quietStart)) {
                        Text(model.quietStart, format: .dateTime.hour().minute())
                    }
                    LabeledContent(String(localized: .quietEnd)) {
                        Text(model.quietEnd, format: .dateTime.hour().minute())
                    }
                }
            } header: {
                Text(.onboardingAppearanceTitle)
            } footer: {
                Text(.onboardingReadyDescription)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var sourceName: String {
        switch model.sourceChoice {
            case .adsbLol: String(localized: .sourceAdsbLol)
            case .readsb: String(localized: .sourceReadsb)
            case .adsbExchange: String(localized: .sourceAdsbExchange)
            case .flightradar24: String(localized: .sourceFlightradar24)
            case nil: "—"
        }
    }

    private var credentialName: String {
        switch model.rapidAPICredentialState {
            case .missing:
                String(localized: .sourceCredentialMissing)
            case let .saved(lastFour):
                if model.hasStagedRapidAPICredential {
                    if let lastFour {
                        "\(String(localized: .sourceCredentialStaged)) · •••• \(lastFour)"
                    } else {
                        String(localized: .sourceCredentialStaged)
                    }
                } else {
                    lastFour.map { "•••• \($0)" } ?? String(localized: .sourceCredentialSaved)
                }
        }
    }

    private var locationModeName: String {
        switch model.locationMode {
            case .gps: String(localized: .locationUseGPS)
            case .manual: String(localized: .locationManual)
        }
    }

    private var coordinateName: String {
        let latitude = model.latitude.formatted(.number.precision(.fractionLength(4 ... 6)))
        let longitude = model.longitude.formatted(.number.precision(.fractionLength(4 ... 6)))
        return "\(latitude), \(longitude)"
    }

    private var modeName: String {
        switch model.selectedMode {
            case .map: String(localized: .modeMap)
            case .trueSky: String(localized: .modeTrueSky)
            case nil: "—"
        }
    }

    private var outputName: String {
        switch model.calibrationOutputChoice {
            case .externalDisplay: String(localized: .calibrationOutputExternal)
            case .fullScreenPreview: String(localized: .calibrationOutputFullScreen)
            case nil: "—"
        }
    }

    private var calibrationStatusName: String {
        model.calibrationVerified
            ? String(localized: .calibrationHealthVerified)
            : String(localized: .calibrationHealthUnverified)
    }

    private var quietName: String {
        model.quietEnabled ? String(localized: .quietEnabled) : String(localized: .quietDisabled)
    }

    private var layerSummary: String {
        switch model.selectedMode {
            case .map: String(localized: .onboardingDefaultLayersMap)
            case .trueSky: String(localized: .onboardingDefaultLayersTrueSky)
            case nil: String(localized: .layerFlights)
        }
    }
}
