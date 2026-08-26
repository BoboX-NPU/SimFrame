import Foundation

@MainActor
final class RecentCaptureStore {
    private let defaults: UserDefaults
    private let key = "recentCaptures.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [RecentCaptureRecord] {
        guard let data = defaults.data(forKey: key),
              let records = try? decoder.decode([RecentCaptureRecord].self, from: data) else { return [] }
        return records.compactMap { record in
            guard resolve(record) != nil else { return nil }
            return record
        }
    }

    func add(url: URL, kind: CaptureKind, to records: [RecentCaptureRecord]) -> [RecentCaptureRecord] {
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return records }
        var updated = records.filter { resolve($0)?.standardizedFileURL != url.standardizedFileURL }
        updated.insert(
            RecentCaptureRecord(
                id: UUID(),
                displayName: url.lastPathComponent,
                bookmark: bookmark,
                kind: kind,
                lastOpenedAt: Date()
            ),
            at: 0
        )
        updated = Array(updated.prefix(8))
        if let data = try? encoder.encode(updated) { defaults.set(data, forKey: key) }
        return updated
    }

    func resolve(_ record: RecentCaptureRecord) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: record.bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}

