#if DEBUG
    import SFSafeSymbols
    import SwiftUI

    struct ProjectorLabView: View {
        let session: ThrowSession
        @State private var model: ProjectorLabModel
        @State private var fixtureSession: ThrowSession
        @State private var usesFixtureTraffic = true
        @Environment(\.throwStylesheet) private var stylesheet

        init(session: ThrowSession, outputID: ProjectionOutputID) {
            self.session = session
            _model = State(
                initialValue: ProjectorLabModel(session: session, outputID: outputID),
            )
            _fixtureSession = State(initialValue: .fixture())
        }

        var body: some View {
            @Bindable var model = model
            ScrollView {
                VStack(alignment: .leading, spacing: stylesheet.spacing.large) {
                    Picker(
                        String(localized: .projectorLabAspectRatio),
                        selection: $model.aspectRatio,
                    ) {
                        ForEach(ProjectorLabAspectRatio.allCases, id: \.self) { aspect in
                            Text(aspect.title).tag(aspect)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle(
                        String(localized: .projectorLabSimulateConnection),
                        isOn: $model.isConnected,
                    )
                    Toggle(
                        String(localized: .projectorLabFixtureTraffic),
                        isOn: $usesFixtureTraffic,
                    )
                    Label(
                        String(localized: model.isConnected
                            ? .projectorLabConnected
                            : .projectorLabDisconnected),
                        systemSymbol: model.isConnected
                            ? .checkmarkCircleFill
                            : .exclamationmarkTriangleFill,
                    )
                    .foregroundStyle(model.isConnected ? Color.green : Color.secondary)

                    ProjectionSurface(
                        session: usesFixtureTraffic ? fixtureSession : session,
                        presentation: .preview,
                    )
                    .aspectRatio(model.aspectRatio.ratio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(.black)
                    .clipShape(.rect(cornerRadius: stylesheet.cornerRadius.medium))
                    .accessibilityLabel(Text(.projectorLabPreview))

                    Text(.projectorLabDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(stylesheet.spacing.large)
            }
            .navigationTitle(Text(.projectorLabTitle))
            .onDisappear(perform: model.disconnect)
        }
    }
#endif
