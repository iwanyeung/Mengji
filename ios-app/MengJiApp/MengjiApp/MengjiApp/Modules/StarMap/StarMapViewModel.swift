import Combine
import SwiftUI

final class StarMapViewModel: ObservableObject {
    // PRD：底部搜索/过滤（文本搜索 + 仅已显化）
    @Published var searchText: String = ""
    @Published var onlyHasComic: Bool = false

    // MARK: - 布局缓存（避免 body 每帧重算 O(n²) 碰撞检测）

    private var _layoutDreamIds: [UUID] = []
    private var _layoutSize: CGSize = .zero
    private var _layoutNodes: [StarMapNode] = []

    private var _edgesFocusId: UUID? = nil
    private var _edgesNodeIds: [UUID] = []
    private var _layoutEdges: [StarMapEdge] = []

    func cachedLayoutNodes(dreams: [Dream], in canvasSize: CGSize) -> [StarMapNode] {
        let ids = dreams.map { $0.id }
        let sameIds = ids == _layoutDreamIds
        let sameSize = abs(canvasSize.width - _layoutSize.width) < 1
            && abs(canvasSize.height - _layoutSize.height) < 1

        guard !sameIds || !sameSize else { return _layoutNodes }

        _layoutDreamIds = ids
        _layoutSize = canvasSize
        _layoutNodes = layoutNodes(dreams: dreams, in: canvasSize)
        return _layoutNodes
    }

    func cachedLayoutEdges(nodes: [StarMapNode], focusDreamId: UUID?) -> [StarMapEdge] {
        let nodeIds = nodes.map { $0.id }
        guard nodeIds != _edgesNodeIds || focusDreamId != _edgesFocusId else { return _layoutEdges }

        _edgesNodeIds = nodeIds
        _edgesFocusId = focusDreamId
        _layoutEdges = layoutEdges(nodes: nodes, focusDreamId: focusDreamId)
        return _layoutEdges
    }

    func filteredDreams(_ dreams: [Dream]) -> [Dream] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = trimmed.lowercased()

        var result = dreams

        if onlyHasComic {
            result = result.filter { $0.hasComic }
        }

        if !q.isEmpty {
            result = result.filter { dream in
                let haystack = [
                    dream.title,
                    dream.organizedText,
                    dream.interpretation,
                    dream.tags.joined(separator: " "),
                ].joined(separator: "\n").lowercased()

                return haystack.contains(q)
            }
        }

        return result.sorted { $0.createdAt > $1.createdAt }
    }

    func layoutNodes(dreams: [Dream], in canvasSize: CGSize) -> [StarMapNode] {
        guard !dreams.isEmpty else { return [] }

        let minDim = min(canvasSize.width, canvasSize.height)
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

        // 基础分布半径：新梦中心，旧梦外围
        let minR = minDim * 0.12
        let maxR = minDim * 0.45

        let total = max(dreams.count, 1)
        var nodes: [StarMapNode] = []

        // 1. 基础布局计算
        for (index, dream) in dreams.enumerated() {
            let t = Double(index) / Double(max(total - 1, 1)) // 0 (newest) -> 1 (oldest)
            
            // 节点大小与亮度：越新越大、越亮
            let nodeScale = CGFloat(1.2 - 0.4 * t)
            let brightness = 1.0 - 0.4 * t

            let radius = CGFloat(minR + (maxR - minR) * t)
            let baseAngle = (2 * Double.pi) * (Double(index) / Double(total))
            
            // 增加更稳定的极坐标偏移，确保分布更开
            let angleJitter = stableRandomUnit(uuid: dream.id, salt: 1) * 0.8
            let radiusJitter = (stableRandomUnit(uuid: dream.id, salt: 4) * 0.15) * radius
            
            let angle = baseAngle + angleJitter
            let finalRadius = radius + radiusJitter

            let dx = CGFloat(cos(angle)) * finalRadius
            let dy = CGFloat(sin(angle)) * finalRadius

            let pos = CGPoint(x: center.x + dx, y: center.y + dy)
            nodes.append(StarMapNode(dream: dream, position: pos, scale: nodeScale, brightness: brightness))
        }

        // 2. 简易碰撞/排斥力微调（迭代一次，防止视觉堆叠）
        let minDistance: CGFloat = 120 // 确保节点间至少有一定间距
        for _ in 0..<1 {
            for i in 0..<nodes.count {
                for j in (i + 1)..<nodes.count {
                    let p1 = nodes[i].position
                    let p2 = nodes[j].position
                    let dx = p1.x - p2.x
                    let dy = p1.y - p2.y
                    let dist = sqrt(dx*dx + dy*dy)

                    if dist < minDistance && dist > 0 {
                        let force = (minDistance - dist) / 2
                        let offset = CGPoint(x: (dx / dist) * force, y: (dy / dist) * force)
                        nodes[i].position = CGPoint(x: nodes[i].position.x + offset.x, y: nodes[i].position.y + offset.y)
                        nodes[j].position = CGPoint(x: nodes[j].position.x - offset.x, y: nodes[j].position.y - offset.y)
                    }
                }
            }
        }

        return nodes
    }

    /// 仅当 `focusDreamId != nil` 时返回与焦点梦境相连的边（用于选中高亮）；未选中时返回空数组。
    func layoutEdges(nodes: [StarMapNode], focusDreamId: UUID?) -> [StarMapEdge] {
        guard nodes.count >= 2, let focus = focusDreamId else { return [] }

        var candidateEdges: [(from: StarMapNode, to: StarMapNode, strength: CGFloat)] = []

        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                let a = nodes[i]
                let b = nodes[j]

                let strength = tagIntersectionStrength(a: a.dream, b: b.dream)
                if strength > 0 {
                    candidateEdges.append((from: a, to: b, strength: strength))
                }
            }
        }

        let incident = candidateEdges.filter { $0.from.dream.id == focus || $0.to.dream.id == focus }
        let chosen: [(from: StarMapNode, to: StarMapNode, strength: CGFloat)]

        if !incident.isEmpty {
            chosen = Array(incident.sorted { $0.strength > $1.strength }.prefix(8))
        } else {
            let sortedByTime = nodes.sorted { $0.dream.createdAt > $1.dream.createdAt }
            guard let idx = sortedByTime.firstIndex(where: { $0.dream.id == focus }) else { return [] }
            var fallback: [(from: StarMapNode, to: StarMapNode, strength: CGFloat)] = []
            if idx > 0 {
                let a = sortedByTime[idx]
                let b = sortedByTime[idx - 1]
                let s = max(tagIntersectionStrength(a: a.dream, b: b.dream), 0.28)
                fallback.append((from: a, to: b, strength: s))
            }
            if idx + 1 < sortedByTime.count {
                let a = sortedByTime[idx]
                let b = sortedByTime[idx + 1]
                let s = max(tagIntersectionStrength(a: a.dream, b: b.dream), 0.28)
                fallback.append((from: a, to: b, strength: s))
            }
            chosen = fallback
        }

        return chosen.map { item in
            Self.makeQuadEdge(
                from: item.from,
                to: item.to,
                strength: item.strength
            )
        }
    }

    private static func makeQuadEdge(from a: StarMapNode, to b: StarMapNode, strength: CGFloat) -> StarMapEdge {
        let p1 = a.position
        let p2 = b.position
        let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)

        let vx = p2.x - p1.x
        let vy = p2.y - p1.y
        let len = sqrt(vx * vx + vy * vy)
        let nx = len == 0 ? 0 : -vy / len
        let ny = len == 0 ? 0 : vx / len

        let curve = strength * 40
        let control = CGPoint(x: mid.x + nx * curve, y: mid.y + ny * curve)

        return StarMapEdge(
            fromDreamId: a.dream.id,
            toDreamId: b.dream.id,
            from: p1,
            to: p2,
            control: control,
            strength: strength
        )
    }

    private func tagIntersectionStrength(a: Dream, b: Dream) -> CGFloat {
        let setA = Set(a.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let setB = Set(b.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let inter = setA.intersection(setB)
        guard !inter.isEmpty else { return 0 }

        // 映射到 [0, 1]
        // 1 个交集 -> 0.35；2 个 -> 0.65；>=3 -> 0.95
        switch inter.count {
        case 1: return 0.35
        case 2: return 0.65
        default: return 0.95
        }
    }

    // 稳定伪随机映射到 [-1, 1]
    private func stableRandomUnit(uuid: UUID, salt: UInt64) -> CGFloat {
        let input = "\(uuid.uuidString)-\(salt)"
        let bytes = Array(input.utf8)

        // FNV-1a 64-bit
        var hash: UInt64 = 14695981039346656037
        for b in bytes {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }

        let v = Double(hash % 20001) / 10000.0 - 1.0 // [-1, 1]
        return CGFloat(v)
    }
}

struct StarMapNode: Identifiable {
    let id: UUID
    let dream: Dream
    var position: CGPoint
    let scale: CGFloat
    let brightness: Double

    init(dream: Dream, position: CGPoint, scale: CGFloat = 1.0, brightness: Double = 1.0) {
        self.id = dream.id
        self.dream = dream
        self.position = position
        self.scale = scale
        self.brightness = brightness
    }
}

struct StarMapEdge: Identifiable {
    let id: String
    let fromDreamId: UUID
    let toDreamId: UUID
    let from: CGPoint
    let to: CGPoint
    let control: CGPoint
    let strength: CGFloat

    init(fromDreamId: UUID, toDreamId: UUID, from: CGPoint, to: CGPoint, control: CGPoint, strength: CGFloat) {
        self.id = "\(fromDreamId.uuidString)-\(toDreamId.uuidString)"
        self.fromDreamId = fromDreamId
        self.toDreamId = toDreamId
        self.from = from
        self.to = to
        self.control = control
        self.strength = strength
    }
}

