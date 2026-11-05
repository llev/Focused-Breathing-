import Foundation

/// The Classical mix: public domain recordings listed in classical.json and served from swellotic.com.
///
/// Each piece downloads the first time it plays and is then kept on the phone, so pieces you've heard work offline.
/// "Save all for offline" downloads the whole set. Turning it off frees the space. Swellotic only ever contacts its own site.
@MainActor
final class ClassicalLibrary: ObservableObject {
    struct Piece: Codable, Equatable {
        let file: String
        let composer: String
        let title: String
        let performer: String

        var heading: String { "\(composer): \(title)" }
    }

    /// The app's own site. The web app at the same address serves the same files.
    static let site = URL(string: "https://swellotic.com/")!

    @Published private(set) var pieces: [Piece] = []
    @Published private(set) var savedCount = 0
    @Published private(set) var savingAll = false

    private let folder: URL
    private var downloads: [String: Task<URL, Error>] = [:]
    private var saveTask: Task<Void, Never>?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("Classical", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The music can be downloaded again, so it stays out of iCloud backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = folder
        try? excluded.setResourceValues(values)

        // Start with the newest list we have: one fetched earlier, or the copy built into the app.
        let cached = folder.appendingPathComponent("classical.json")
        if let data = try? Data(contentsOf: cached), let list = try? JSONDecoder().decode([Piece].self, from: data), !list.isEmpty {
            pieces = list
        } else if let url = Bundle.main.url(forResource: "classical", withExtension: "json"),
                  let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([Piece].self, from: data) {
            pieces = list
        }
        countSaved()
        Task { await refreshList() }
    }

    /// Fetches the latest list from the site, so pieces can change without an App Store update.
    func refreshList() async {
        let url = Self.site.appendingPathComponent("classical.json")
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONDecoder().decode([Piece].self, from: data), !list.isEmpty else { return }
        try? data.write(to: folder.appendingPathComponent("classical.json"))
        if list != pieces { pieces = list }
        countSaved()
    }

    private func localURL(_ piece: Piece) -> URL {
        folder.appendingPathComponent((piece.file as NSString).lastPathComponent)
    }

    func isSaved(_ index: Int) -> Bool {
        guard pieces.indices.contains(index) else { return false }
        return FileManager.default.fileExists(atPath: localURL(pieces[index]).path)
    }

    private func countSaved() {
        savedCount = pieces.indices.filter(isSaved).count
    }

    /// The piece on the phone, downloading it first if needed.
    func fetch(_ index: Int) async throws -> URL {
        let piece = pieces[index]
        let local = localURL(piece)
        if FileManager.default.fileExists(atPath: local.path) { return local }
        if let running = downloads[piece.file] { return try await running.value }
        let remote = Self.site.appendingPathComponent(piece.file)
        let task = Task<URL, Error> {
            let (temp, response) = try await URLSession.shared.download(from: remote)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            try? FileManager.default.removeItem(at: local)
            try FileManager.default.moveItem(at: temp, to: local)
            return local
        }
        downloads[piece.file] = task
        defer { downloads[piece.file] = nil }
        let url = try await task.value
        countSaved()
        return url
    }

    /// The next piece from `index` in the direction of `step` that can play now. Offline, that's the next saved one.
    func playable(from index: Int, step: Int, online: Bool) -> Int {
        let n = pieces.count
        guard n > 0 else { return 0 }
        var i = ((index % n) + n) % n
        if online || savedCount == 0 { return i }
        for _ in 0..<n {
            if isSaved(i) { return i }
            i = ((i + step) % n + n) % n
        }
        return i
    }

    func setSaveAll(_ on: Bool) {
        saveTask?.cancel()
        if on {
            savingAll = true
            saveTask = Task { [weak self] in
                guard let self else { return }
                for i in self.pieces.indices where !self.isSaved(i) {
                    if Task.isCancelled { break }
                    _ = try? await self.fetch(i)
                }
                self.savingAll = false
            }
        } else {
            savingAll = false
            // Turning it off frees the space. Pieces you listen to are kept again as you hear them.
            for piece in pieces { try? FileManager.default.removeItem(at: localURL(piece)) }
            countSaved()
        }
    }

    /// Carries on saving after the app restarts or comes back online.
    func resumeSaving(_ saveAll: Bool) {
        if saveAll && savedCount < pieces.count && !savingAll { setSaveAll(true) }
    }
}
