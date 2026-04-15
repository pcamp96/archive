import Foundation

@MainActor
final class BookmarkStore {
    private enum Keys {
        static let recentWorkspaces = "recentWorkspaces"
        static let lastWorkspace = "lastWorkspace"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func makeBookmark(for url: URL, existing: Data?) throws -> Data {
        if let existing {
            return existing
        }
        return try url.bookmarkData()
    }

    func loadRecents() -> [RecentWorkspace] {
        guard let data = defaults.data(forKey: Keys.recentWorkspaces) else { return [] }
        return (try? JSONDecoder().decode([RecentWorkspace].self, from: data)) ?? []
    }

    func loadLastWorkspace() -> RecentWorkspace? {
        guard let data = defaults.data(forKey: Keys.lastWorkspace) else { return nil }
        return try? JSONDecoder().decode(RecentWorkspace.self, from: data)
    }

    func recordWorkspace(url: URL, bookmarkData: Data) {
        let recent = RecentWorkspace(path: url.path, bookmarkData: bookmarkData)
        var recents = loadRecents().filter { $0.path != recent.path }
        recents.insert(recent, at: 0)
        recents = Array(recents.prefix(10))

        if let data = try? JSONEncoder().encode(recents) {
            defaults.set(data, forKey: Keys.recentWorkspaces)
        }
        if let data = try? JSONEncoder().encode(recent) {
            defaults.set(data, forKey: Keys.lastWorkspace)
        }
    }
}

