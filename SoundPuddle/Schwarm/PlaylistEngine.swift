import Foundation

struct PlaylistTrack: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var title: String
    /// Host-only local path; joiners only see title/id.
    var path: String?
    var votes: Int

    init(id: String = UUID().uuidString, title: String, path: String? = nil, votes: Int = 0) {
        self.id = id
        self.title = title
        self.path = path
        self.votes = votes
    }
}

@MainActor
final class PlaylistEngine {
    private(set) var tracks: [PlaylistTrack] = []
    private(set) var currentID: String?
    private var voterChoices: [String: String] = [:] // peerID → trackID

    var current: PlaylistTrack? {
        tracks.first { $0.id == currentID }
    }

    var ranked: [PlaylistTrack] {
        tracks.sorted { $0.votes > $1.votes }
    }

    func replace(with items: [PlaylistTrack], current: String?) {
        tracks = items
        currentID = current ?? items.first?.id
        voterChoices.removeAll()
    }

    func add(_ track: PlaylistTrack) {
        tracks.append(track)
        if currentID == nil { currentID = track.id }
    }

    func vote(trackID: String, from peerID: String) {
        if let prev = voterChoices[peerID], let idx = tracks.firstIndex(where: { $0.id == prev }) {
            tracks[idx].votes = max(0, tracks[idx].votes - 1)
        }
        voterChoices[peerID] = trackID
        if let idx = tracks.firstIndex(where: { $0.id == trackID }) {
            tracks[idx].votes += 1
        }
    }

    func winningNext(excludingCurrent: Bool = true) -> PlaylistTrack? {
        let pool = tracks.filter { !excludingCurrent || $0.id != currentID }
        return pool.max(by: { $0.votes < $1.votes })
    }

    func advanceToWinner() -> PlaylistTrack? {
        guard let next = winningNext() else { return nil }
        currentID = next.id
        for i in tracks.indices { tracks[i].votes = 0 }
        voterChoices.removeAll()
        return next
    }

    func snapshotPayload() -> (tracks: [PlaylistTrack], currentID: String?) {
        // Strip paths for wire
        let wire = tracks.map { PlaylistTrack(id: $0.id, title: $0.title, path: nil, votes: $0.votes) }
        return (wire, currentID)
    }
}
