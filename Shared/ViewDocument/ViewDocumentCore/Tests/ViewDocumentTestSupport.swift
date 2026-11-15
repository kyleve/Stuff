import ViewDocumentCore

func documentNode(
    _ name: String,
    content: ViewDocument.Content,
    modifiers: [ViewModifierDescriptor] = [],
    animation: ViewAnimationDescriptor? = nil,
) -> ViewDocument.Node {
    .init(
        id: .init(rawValue: name),
        content: content,
        modifiers: modifiers,
        animation: animation,
        accessibility: .automatic,
    )
}

let noDocumentResources = ViewDocumentResources(images: [], symbols: [])
