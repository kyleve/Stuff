/// The two overview presentations Flyover supports.
public enum FlyoverViewMode: String, CaseIterable, Identifiable, Sendable {
    case canvas
    case list

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
            case .canvas: "Canvas"
            case .list: "List"
        }
    }
}
