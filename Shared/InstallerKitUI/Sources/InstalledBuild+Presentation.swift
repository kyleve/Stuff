import InstallerKit
import SwiftUI

extension InstalledBuild.Source {
    var channelLabel: Text {
        switch self {
            case .local: Text(.installerLocalChannel)
            case let .published(publication): Text(verbatim: publication.channel.rawValue)
        }
    }
}
