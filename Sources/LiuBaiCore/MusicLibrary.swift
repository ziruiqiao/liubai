import Foundation

extension AppData {
    public var myMusic: [Track] { tracks(for: myMusicKeys ?? legacyMyMusicKeys) }

    public func tracks(in collection: LibraryCollection) -> [Track] { tracks(for: collection.trackKeys) }

    public func tracks(for keys: [String]) -> [Track] {
        let index = Dictionary(tracks.map { ($0.libraryKey, $0) }, uniquingKeysWith: { first, _ in first })
        return keys.compactMap { index[$0] }
    }

    /// The old individual-import path always resolved CID; folder/season
    /// imports kept CID = 0. Multi-part imports already retained their group.
    private var legacyMyMusicKeys: [String] {
        let partKeys = Set((collections ?? []).filter { $0.kind == .parts }.flatMap(\.trackKeys))
        return tracks.filter { $0.cid > 0 && !partKeys.contains($0.libraryKey) }.map(\.libraryKey)
    }

    @discardableResult
    public mutating func migrateMusicMembership() -> Bool {
        guard myMusicKeys == nil else { return false }
        myMusicKeys = legacyMyMusicKeys
        pruneUnusedMusic()
        return true
    }

    @discardableResult
    public mutating func addToMyMusic(_ track: Track) -> Bool {
        migrateMusicMembership()
        var keys = myMusicKeys ?? []
        guard !keys.contains(track.libraryKey) else { return false }
        if let index = tracks.firstIndex(where: { $0.libraryKey == track.libraryKey }) {
            // Preserve existing collection membership and import date while
            // retaining the CID resolved by the explicit individual import.
            var resolved = track
            resolved.addedAt = tracks[index].addedAt
            tracks[index] = resolved
        } else { tracks.append(track) }
        keys.append(track.libraryKey)
        myMusicKeys = keys
        return true
    }

    @discardableResult
    public mutating func addCollection(_ preview: LibraryPreview, selected: Set<String>) -> (added: Int, duplicates: Int) {
        migrateMusicMembership()
        var chosenKeys = Set<String>()
        let chosen = preview.tracks.filter { selected.contains($0.libraryKey) && chosenKeys.insert($0.libraryKey).inserted }
        var metadataKeys = Set(tracks.map(\.libraryKey))
        for track in chosen where metadataKeys.insert(track.libraryKey).inserted { tracks.append(track) }
        var groups = collections ?? []
        var added = 0
        if let index = groups.firstIndex(where: { $0.id == preview.id }) {
            var existing = Set(groups[index].trackKeys)
            let newKeys = chosen.map(\.libraryKey).filter { existing.insert($0).inserted }
            groups[index].trackKeys.append(contentsOf: newKeys)
            groups[index].title = preview.title
            added = newKeys.count
        } else {
            let keys = chosen.map(\.libraryKey)
            groups.append(LibraryCollection(id: preview.id, title: preview.title, kind: preview.kind, sourceURL: preview.sourceURL, trackKeys: keys))
            added = keys.count
        }
        collections = groups
        return (added, chosen.count - added)
    }

    public mutating func removeCollection(id: String) {
        migrateMusicMembership()
        collections = (collections ?? []).filter { $0.id != id }
        pruneUnusedMusic()
    }

    public mutating func removeMusic(key: String, from collectionID: String? = nil) {
        migrateMusicMembership()
        if let collectionID {
            if let index = collections?.firstIndex(where: { $0.id == collectionID }) {
                collections?[index].trackKeys.removeAll { $0 == key }
            }
        } else { myMusicKeys?.removeAll { $0 == key } }
        pruneUnusedMusic()
    }

    public mutating func moveMusic(key: String, by delta: Int, in collectionID: String? = nil) {
        migrateMusicMembership()
        if let collectionID, let group = collections?.firstIndex(where: { $0.id == collectionID }),
           let index = collections?[group].trackKeys.firstIndex(of: key),
           collections![group].trackKeys.indices.contains(index + delta) {
            collections?[group].trackKeys.swapAt(index, index + delta)
        } else if collectionID == nil, let index = myMusicKeys?.firstIndex(of: key),
                  myMusicKeys!.indices.contains(index + delta) {
            myMusicKeys?.swapAt(index, index + delta)
        }
    }

    /// Shared songs survive as long as an individual import or another group
    /// still owns them. Removing a group never turns its songs into my music.
    public mutating func pruneUnusedMusic() {
        let retained = Set((myMusicKeys ?? legacyMyMusicKeys) + (collections ?? []).flatMap(\.trackKeys))
        tracks.removeAll { !retained.contains($0.libraryKey) }
    }

    public mutating func removeImportedFavorites() {
        migrateMusicMembership()
        collections = (collections ?? []).filter { $0.kind != .favorites }
        pruneUnusedMusic()
    }
}
