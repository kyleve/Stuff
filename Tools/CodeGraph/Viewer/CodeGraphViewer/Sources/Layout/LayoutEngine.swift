import CoreGraphics
import Foundation

/// A self-contained description of what to lay out, decoupled from the model so
/// it can cross the actor boundary cheaply.
struct LayoutInput {
    struct Node {
        var id: String
        var module: String
    }

    struct Edge {
        var source: String
        var target: String
        var weight: Double
    }

    var nodes: [Node]
    var edges: [Edge]
    /// Nodes the user dragged: held fixed but still repel/attract others.
    var pinned: [String: CGPoint]
    var size: CGSize
}

/// Force-directed (Fruchterman–Reingold) layout with module-centroid gravity,
/// grid-accelerated repulsion, deterministic seeding, and pinned nodes.
///
/// Runs off the main actor so a large graph can settle without janking the UI.
actor LayoutEngine {
    /// Settle the graph and return a position per node id.
    func layout(_ input: LayoutInput, iterations: Int? = nil) -> [String: CGPoint] {
        let nodes = input.nodes
        let count = nodes.count
        guard count > 0 else { return [:] }

        let width = max(Double(input.size.width), 400)
        let height = max(Double(input.size.height), 400)
        let centerX = width / 2
        let centerY = height / 2
        // Ideal edge length; floored so dense clusters stay legible.
        let k = max(36.0, (width * height / Double(count)).squareRoot())
        let steps = iterations ?? adaptiveIterations(for: count)

        var index = [String: Int](minimumCapacity: count)
        for (i, node) in nodes.enumerated() {
            index[node.id] = i
        }

        var posX = [Double](repeating: 0, count: count)
        var posY = [Double](repeating: 0, count: count)
        seedPositions(
            into: &posX,
            &posY,
            centerX: centerX,
            centerY: centerY,
            radius: min(centerX, centerY),
        )

        var pinnedIndices = Set<Int>()
        for (id, point) in input.pinned {
            guard let i = index[id] else { continue }
            posX[i] = Double(point.x)
            posY[i] = Double(point.y)
            pinnedIndices.insert(i)
        }

        let edges: [(Int, Int, Double)] = input.edges.compactMap { edge in
            guard let source = index[edge.source], let target = index[edge.target],
                  source != target
            else {
                return nil
            }
            return (source, target, edge.weight)
        }

        var dispX = [Double](repeating: 0, count: count)
        var dispY = [Double](repeating: 0, count: count)
        var temperature = min(width, height) / 6
        let cooling = pow(2.0 / max(temperature, 2), 1.0 / Double(max(steps, 1)))
        var rng = SplitMix64(seed: 0xD1B5_4A32_D192_ED03)

        for _ in 0 ..< steps {
            for i in 0 ..< count {
                dispX[i] = 0
                dispY[i] = 0
            }
            applyRepulsion(posX: posX, posY: posY, dispX: &dispX, dispY: &dispY, k: k, rng: &rng)
            applyAttraction(
                edges: edges,
                posX: posX,
                posY: posY,
                dispX: &dispX,
                dispY: &dispY,
                k: k,
            )
            applyModuleGravity(nodes: nodes, posX: posX, posY: posY, dispX: &dispX, dispY: &dispY)
            integrate(
                posX: &posX,
                posY: &posY,
                dispX: dispX,
                dispY: dispY,
                pinned: pinnedIndices,
                temperature: temperature,
            )
            temperature = max(temperature * cooling, 1)
        }

        var result = [String: CGPoint](minimumCapacity: count)
        for i in 0 ..< count {
            result[nodes[i].id] = CGPoint(x: posX[i], y: posY[i])
        }
        return result
    }

    // MARK: - Forces

    /// Grid-bucketed repulsion: each node is pushed only by others in its own
    /// and adjacent cells, which keeps the cost ~O(n) for spread-out graphs
    /// while distant pairs contribute negligibly anyway.
    private func applyRepulsion(
        posX: [Double],
        posY: [Double],
        dispX: inout [Double],
        dispY: inout [Double],
        k: Double,
        rng: inout SplitMix64,
    ) {
        let count = posX.count
        let cellSize = k
        var grid = [Cell: [Int]]()
        for i in 0 ..< count {
            grid[Cell(posX[i], posY[i], cellSize), default: []].append(i)
        }

        let k2 = k * k
        for i in 0 ..< count {
            let cell = Cell(posX[i], posY[i], cellSize)
            for neighbor in cell.neighborhood() {
                guard let bucket = grid[neighbor] else { continue }
                for j in bucket where j != i {
                    var dx = posX[i] - posX[j]
                    var dy = posY[i] - posY[j]
                    var dist2 = dx * dx + dy * dy
                    if dist2 < 0.01 {
                        dx = rng.nextUnit() - 0.5
                        dy = rng.nextUnit() - 0.5
                        dist2 = dx * dx + dy * dy + 0.01
                    }
                    let dist = dist2.squareRoot()
                    let force = k2 / dist
                    dispX[i] += dx / dist * force
                    dispY[i] += dy / dist * force
                }
            }
        }
    }

    private func applyAttraction(
        edges: [(Int, Int, Double)],
        posX: [Double],
        posY: [Double],
        dispX: inout [Double],
        dispY: inout [Double],
        k: Double,
    ) {
        for (source, target, weight) in edges {
            let dx = posX[source] - posX[target]
            let dy = posY[source] - posY[target]
            let dist = max((dx * dx + dy * dy).squareRoot(), 0.01)
            let force = dist * dist / k * weight
            let fx = dx / dist * force
            let fy = dy / dist * force
            dispX[source] -= fx
            dispY[source] -= fy
            dispX[target] += fx
            dispY[target] += fy
        }
    }

    private func applyModuleGravity(
        nodes: [LayoutInput.Node],
        posX: [Double],
        posY: [Double],
        dispX: inout [Double],
        dispY: inout [Double],
    ) {
        var sumX = [String: Double]()
        var sumY = [String: Double]()
        var counts = [String: Int]()
        for i in 0 ..< nodes.count {
            let module = nodes[i].module
            sumX[module, default: 0] += posX[i]
            sumY[module, default: 0] += posY[i]
            counts[module, default: 0] += 1
        }
        let pull = 0.06
        for i in 0 ..< nodes.count {
            let module = nodes[i].module
            guard let n = counts[module], n > 0 else { continue }
            let centroidX = sumX[module]! / Double(n)
            let centroidY = sumY[module]! / Double(n)
            dispX[i] += (centroidX - posX[i]) * pull
            dispY[i] += (centroidY - posY[i]) * pull
        }
    }

    private func integrate(
        posX: inout [Double],
        posY: inout [Double],
        dispX: [Double],
        dispY: [Double],
        pinned: Set<Int>,
        temperature: Double,
    ) {
        for i in 0 ..< posX.count where !pinned.contains(i) {
            let magnitude = (dispX[i] * dispX[i] + dispY[i] * dispY[i]).squareRoot()
            guard magnitude > 0 else { continue }
            let limited = min(magnitude, temperature)
            posX[i] += dispX[i] / magnitude * limited
            posY[i] += dispY[i] / magnitude * limited
        }
    }

    // MARK: - Seeding & tuning

    private func seedPositions(
        into posX: inout [Double],
        _ posY: inout [Double],
        centerX: Double,
        centerY: Double,
        radius: Double,
    ) {
        // A deterministic phyllotaxis spiral spreads the seed evenly and
        // reproducibly, so the same graph always settles the same way.
        let golden = Double.pi * (3 - 5.0.squareRoot())
        let count = posX.count
        for i in 0 ..< count {
            let t = Double(i) + 0.5
            let r = radius * (t / Double(count)).squareRoot()
            let angle = t * golden
            posX[i] = centerX + r * cos(angle)
            posY[i] = centerY + r * sin(angle)
        }
    }

    private func adaptiveIterations(for count: Int) -> Int {
        switch count {
            case ..<200: 500
            case ..<600: 360
            case ..<1500: 240
            default: 160
        }
    }
}

/// Integer grid cell used to bucket nodes for neighborhood repulsion.
private struct Cell: Hashable {
    var x: Int
    var y: Int

    init(_ px: Double, _ py: Double, _ size: Double) {
        x = Int((px / size).rounded(.down))
        y = Int((py / size).rounded(.down))
    }

    init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    func neighborhood() -> [Cell] {
        var cells = [Cell]()
        cells.reserveCapacity(9)
        for dx in -1 ... 1 {
            for dy in -1 ... 1 {
                cells.append(Cell(x: x + dx, y: y + dy))
            }
        }
        return cells
    }
}

/// Small, fast, deterministic PRNG so seeding and jitter are reproducible.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A reproducible double in [0, 1).
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
