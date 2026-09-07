import BroadwayCore
import BroadwayUI
import SwiftUI

struct DaylightStylesheet: BStylesheet {
    struct Preview: Equatable {
        var aspectRatio: CGFloat = 4 / 3
        var cornerRadius: CGFloat = 18
        var background = Color.black
    }

    struct Capture: Equatable {
        var spacing: CGFloat = 24
        var padding: CGFloat = 24
        var background = Color.black
        var foreground = Color.white
    }

    var preview = Preview()
    var capture = Capture()
    static let `default` = Self()
    init() {}
    init(context _: SlicingContext) {
        self.init()
    }
}

extension EnvironmentValues {
    var daylightStylesheet: DaylightStylesheet {
        bContext.stylesheet(
            DaylightStylesheet.self,
            fallback: .default,
        )
    }
}
