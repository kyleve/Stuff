import PortholeCore

extension PortholeExecutionOwnership {
    var presentationTitle: String {
        switch self {
            case .unisolated: "Unisolated"
            case .mainActor: "Main actor"
            case let .actorInstance(typeName): "Actor instance: \(typeName)"
            case .adapter: "Adapter-managed execution"
        }
    }
}
