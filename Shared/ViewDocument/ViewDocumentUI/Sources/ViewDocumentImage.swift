import SwiftUI
import ViewDocumentCore

/// Fill clips at the proposed image bounds; tiling is one native paint operation.
struct ViewDocumentImage: View {
    let image: Image
    let sizing: ViewImageDescriptor.Sizing

    var body: some View {
        switch sizing {
            case .fit: image.resizable().scaledToFit()
            case .fill:
                GeometryReader { geometry in
                    image.resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            case let .tile(scale):
                Rectangle().fill(ImagePaint(image: image, scale: scale))
        }
    }
}
