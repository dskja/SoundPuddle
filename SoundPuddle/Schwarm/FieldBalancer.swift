import Foundation

/// Assigns table seats from peer set + optional ranging distances; rebalances on drop-in/out.
enum FieldBalancer {
    static func rebalance(
        peers: [(id: String, name: String)],
        hostID: String,
        hostName: String,
        distances: [String: Double],
        previous: FieldMap
    ) -> FieldMap {
        var seats: [FieldSeat] = [
            FieldSeat(id: hostID, name: hostName, role: .mid, angleDeg: 0, distanceM: 0)
        ]

        let others = peers.filter { $0.id != hostID }
        guard !others.isEmpty else {
            return FieldMap(seats: seats, version: previous.version + 1)
        }

        // Prefer previous roles when still valid; otherwise place by distance (near→side, far→far).
        let roles = Self.roles(forCount: others.count)
        let sorted = others.sorted { a, b in
            let da = distances[a.id] ?? previous.seats.first(where: { $0.id == a.id })?.distanceM ?? 2.0
            let db = distances[b.id] ?? previous.seats.first(where: { $0.id == b.id })?.distanceM ?? 2.0
            return da < db
        }

        let angleStep = 360.0 / Double(max(others.count, 1))
        for (idx, peer) in sorted.enumerated() {
            let role = roles[idx]
            let prev = previous.seats.first(where: { $0.id == peer.id })
            let dist = distances[peer.id] ?? prev?.distanceM ?? (1.2 + Double(idx) * 0.35)
            let angle = prev?.angleDeg ?? (angleStep * Double(idx) - 90)
            seats.append(FieldSeat(
                id: peer.id,
                name: peer.name,
                role: role,
                angleDeg: angle,
                distanceM: dist
            ))
        }

        return FieldMap(seats: seats, version: previous.version + 1)
    }

    private static func roles(forCount n: Int) -> [SpeakerRole] {
        switch n {
        case 0: return []
        case 1: return [.left]
        case 2: return [.left, .right]
        case 3: return [.left, .right, .farLeft]
        case 4: return [.left, .right, .farLeft, .farRight]
        default:
            var r: [SpeakerRole] = [.left, .right, .farLeft, .farRight]
            while r.count < n { r.append(r.count % 2 == 0 ? .left : .right) }
            return Array(r.prefix(n))
        }
    }
}
