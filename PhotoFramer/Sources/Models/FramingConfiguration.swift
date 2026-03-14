import SwiftUI

struct FramingConfiguration {
    var frameSize: FrameSize
    var mode: FramingMode
    var matColor: Color
    var outputResolution: Int

    static let `default` = FramingConfiguration(
        frameSize: FrameSize.allSizes[0],
        mode: .cropToFill,
        matColor: .white,
        outputResolution: 3000
    )
}
