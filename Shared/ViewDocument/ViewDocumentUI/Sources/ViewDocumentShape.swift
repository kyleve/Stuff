import SwiftUI
import ViewDocumentCore

struct ViewDocumentShape: Shape {
    let descriptor: ViewShapeDescriptor

    func path(in rect: CGRect) -> Path {
        switch descriptor {
            case .rectangle: Rectangle().path(in: rect)
            case let .roundedRectangle(radius): RoundedRectangle(cornerRadius: radius)
            .path(in: rect)
            case .circle: Circle().path(in: rect)
            case .ellipse: Ellipse().path(in: rect)
        }
    }
}
