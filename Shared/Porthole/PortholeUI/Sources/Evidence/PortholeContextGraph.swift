import PortholeCore

/// A focused graph keeps every edge in the capture's original scope generation.
struct PortholeContextGraph {
    enum Direction: Hashable { case incoming, outgoing }
    struct Edge: Identifiable {
        struct ID: Hashable {
            let direction: Direction; let contextID: PortholeContextID; let index: Int
        }

        let id: ID
        let relation: String
        let reference: PortholeEvidenceReference
    }

    let context: PortholeContext
    let incoming: [Edge]
    let outgoing: [Edge]

    init(context: PortholeContext, knownContexts: [PortholeContext]) {
        self.context = context
        let sameScope = knownContexts.filter { $0.scope == context.scope }
        incoming = sameScope.flatMap { source in
            source.links.enumerated().compactMap { index, link in
                guard link.id == context.id else { return nil }
                return Edge(
                    id: .init(direction: .incoming, contextID: source.id, index: index),
                    relation: link.relation,
                    reference: .context(source),
                )
            }
        }
        outgoing = context.links.enumerated().map { index, link in
            let target = sameScope.first(where: { $0.id == link.id })
            return Edge(
                id: .init(direction: .outgoing, contextID: context.id, index: index),
                relation: link.relation,
                reference: target.map(PortholeEvidenceReference.context) ?? .contextLink(
                    link,
                    scope: context.scope,
                ),
            )
        }
    }
}
