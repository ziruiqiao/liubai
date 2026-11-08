import Foundation
import LiuBaiCore

enum MusicMembershipChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw MembershipFailure(message: message) }
            count += 1
        }
        func track(_ index: Int, cid: Int64 = 0, page: Int = 1) -> Track {
            Track(bvid: String(format: "BV%010d", index), cid: cid, title: "声音 \(index)", artist: "UP", duration: 600, page: page)
        }
        func preview(_ id: String, _ tracks: [Track], kind: LibrarySourceKind = .season) -> LibraryPreview {
            LibraryPreview(id: id, title: id, kind: kind, sourceURL: "https://www.bilibili.com/", tracks: tracks)
        }
        func add(_ preview: LibraryPreview, to library: inout AppData) {
            library.addCollection(preview, selected: Set(preview.tracks.map(\.libraryKey)))
        }

        var library = AppData()
        let manual = track(1, cid: 101), shared = track(2), seasonOnly = track(3), favoriteOnly = track(4)
        library.addToMyMusic(manual)
        add(preview("season", [manual, shared, seasonOnly]), to: &library)
        add(preview("favorites", [shared, favoriteOnly], kind: .favorites), to: &library)
        try check(library.myMusic.map(\.libraryKey) == [manual.libraryKey], "Collection and favorite imports must never enter My Music")
        try check(library.tracks.count == 4, "Shared metadata must deduplicate while source memberships remain separate")
        let repeatImport = library.addCollection(preview("season", [seasonOnly, shared]), selected: [seasonOnly.libraryKey, shared.libraryKey])
        try check(repeatImport.added == 0 && repeatImport.duplicates == 2, "Reimport must deduplicate within its own collection")
        library.removeCollection(id: "favorites")
        try check(!library.tracks.contains { $0.libraryKey == favoriteOnly.libraryKey }, "Deleting a collection must remove its unshared songs")
        try check(library.tracks.contains { $0.libraryKey == shared.libraryKey }, "Deleting one group must preserve another group's shared song")
        try check(library.myMusic.map(\.libraryKey) == [manual.libraryKey], "Deleting a group must never promote its songs into My Music")
        library.removeMusic(key: manual.libraryKey)
        try check(library.myMusic.isEmpty && library.tracks.contains { $0.libraryKey == manual.libraryKey }, "Removing individual membership must preserve a collection's copy")
        library.addToMyMusic(track(2, cid: 202))
        try check(library.myMusic.count == 1 && library.myMusic.first?.cid == 202, "Explicitly adding a collection song must create independent My Music membership")
        library.removeCollection(id: "season")
        try check(library.tracks.map(\.libraryKey) == [shared.libraryKey] && library.myMusic.count == 1, "Deleting the last group must preserve only explicitly saved songs")
        library.removeMusic(key: shared.libraryKey)
        try check(library.tracks.isEmpty, "Deleting the last membership must remove its metadata")

        var ordered = AppData()
        ordered.addToMyMusic(manual); ordered.addToMyMusic(track(2, cid: 202))
        add(preview("a", [manual, shared]), to: &ordered)
        add(preview("b", [manual, shared]), to: &ordered)
        ordered.moveMusic(key: manual.libraryKey, by: 1, in: "a")
        try check(ordered.collections?[0].trackKeys == [shared.libraryKey, manual.libraryKey]
                  && ordered.collections?[1].trackKeys == [manual.libraryKey, shared.libraryKey]
                  && ordered.myMusic.first?.libraryKey == manual.libraryKey, "Reordering a collection must not reorder another source")
        ordered.removeMusic(key: manual.libraryKey, from: "a")
        try check(ordered.collections?[0].trackKeys == [shared.libraryKey]
                  && ordered.collections?[1].trackKeys.contains(manual.libraryKey) == true
                  && ordered.myMusic.count == 2, "Removing a song inside a group must affect only that group")
        ordered.moveMusic(key: manual.libraryKey, by: 1)
        try check(ordered.myMusic.last?.libraryKey == manual.libraryKey && ordered.collections?[1].trackKeys.first == manual.libraryKey,
                  "Reordering My Music must not reorder a collection")

        var cleanup = AppData()
        cleanup.addToMyMusic(manual)
        add(preview("season", [shared, seasonOnly]), to: &cleanup)
        add(preview("fav1", [manual, shared, favoriteOnly], kind: .favorites), to: &cleanup)
        add(preview("fav2", [track(5)], kind: .favorites), to: &cleanup)
        cleanup.removeImportedFavorites()
        try check(cleanup.collections?.map(\.id) == ["season"] && cleanup.tracks.count == 3 && cleanup.myMusic.count == 1,
                  "Removing all imported favorites must preserve manual music and UP collections")

        var legacy = AppData()
        legacy.tracks = [manual, shared, seasonOnly, favoriteOnly]
        legacy.collections = [LibraryCollection(id: "season", title: "合集", kind: .season, sourceURL: "", trackKeys: [manual.libraryKey, shared.libraryKey, seasonOnly.libraryKey])]
        legacy.intention = "保留当前状态"
        var journal = JournalEntry(id: "2026-11-08", updatedAt: Date(timeIntervalSince1970: 1_700_000_000)); journal.body = "保存手记"
        legacy.journal[journal.id] = journal
        var json = try JSONSerialization.jsonObject(with: FileStore.encode(legacy)) as! [String: Any]
        json.removeValue(forKey: "myMusicKeys")
        let original = try JSONSerialization.data(withJSONObject: json)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("liubai-membership-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = FileStore(directory: directory)
        try original.write(to: store.fileURL)
        let migrated = try store.load()
        try check(migrated.myMusic.map(\.libraryKey) == [manual.libraryKey], "Legacy individual imports must remain separate even when shared with a group")
        try check(!migrated.tracks.contains { $0.libraryKey == favoriteOnly.libraryKey } && migrated.tracks.count == 3,
                  "Legacy deleted-group leftovers must be pruned rather than appearing in My Music")
        try check(migrated.intention == legacy.intention && migrated.journal[journal.id] == journal && migrated.timer == legacy.timer,
                  "Membership migration must preserve diary, intention, and timer")
        let backup = try Data(contentsOf: store.backupURL)
        try check(backup == original, "Membership migration must retain the complete original document as backup")
        let roundTrip = try store.load()
        try check(roundTrip.myMusicKeys == migrated.myMusicKeys && roundTrip.collections == migrated.collections,
                  "Source separation must survive restart without repeating migration")

        var oldParts = AppData()
        oldParts.myMusicKeys = nil
        oldParts.tracks = [manual, track(6, cid: 601), track(6, cid: 602, page: 2)]
        oldParts.collections = [LibraryCollection(id: "parts", title: "分 P", kind: .parts, sourceURL: "", trackKeys: oldParts.tracks.dropFirst().map(\.libraryKey))]
        oldParts.migrateMusicMembership()
        try check(oldParts.myMusic.count == 1 && oldParts.tracks.count == 3, "Resolved multi-part imports must remain in their collection during legacy migration")
        return count
    }
}

private struct MembershipFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
