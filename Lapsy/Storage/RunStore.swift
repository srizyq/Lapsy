import Foundation
import Observation

/// Finished runs and saved routes. Everything is written to the phone first, so it
/// works offline, then backed up to the signed-in account in Supabase.
@MainActor @Observable
final class RunStore {
    private(set) var runs: [SavedRun] = []      // newest first
    private(set) var routes: [SavedRoute] = []  // newest first
    private(set) var lastSyncError: String?

    @ObservationIgnored private weak var account: AccountStore?
    @ObservationIgnored private var userKey = "local"
    @ObservationIgnored private var pendingDeletes: Set<String> = []   // "runs:<uuid>" / "saved_routes:<uuid>"
    @ObservationIgnored private var syncing = false

    // MARK: - Setup

    func attach(_ account: AccountStore) { self.account = account }

    /// Call when the signed-in person changes (nil = signed out / local only).
    func switchUser(_ id: String?) {
        userKey = id ?? "local"
        load()
        Task { await sync() }
    }

    // MARK: - Derived

    var totalDistanceM: Double { runs.reduce(0) { $0 + $1.distanceM } }
    var totalTimeS: Double { runs.reduce(0) { $0 + $1.durationS } }

    /// Days in a row with at least one outing, counting back from today (or yesterday).
    var streakDays: Int {
        let calendar = Calendar.current
        let days = Set(runs.map { calendar.startOfDay(for: $0.startedAt) })
        var day = calendar.startOfDay(for: Date())
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    // MARK: - Runs

    func add(_ run: SavedRun) {
        var run = run
        run.synced = false
        write(run, folder: "runs", id: run.id)
        runs = (runs.filter { $0.id != run.id } + [run]).sorted { $0.startedAt > $1.startedAt }
        Task { await sync() }
    }

    func setRating(_ rating: Int, for id: UUID) {
        guard var run = runs.first(where: { $0.id == id }) else { return }
        run.rating = rating
        add(run)
    }

    func delete(_ run: SavedRun) {
        remove(folder: "runs", id: run.id)
        runs.removeAll { $0.id == run.id }
        if run.synced { pendingDeletes.insert("runs:\(run.id.uuidString.lowercased())"); savePending() }
        Task { await sync() }
    }

    // MARK: - Saved routes

    func add(_ route: SavedRoute) {
        var route = route
        route.synced = false
        write(route, folder: "routes", id: route.id)
        routes = (routes.filter { $0.id != route.id } + [route]).sorted { $0.createdAt > $1.createdAt }
        Task { await sync() }
    }

    func delete(_ route: SavedRoute) {
        remove(folder: "routes", id: route.id)
        routes.removeAll { $0.id == route.id }
        if route.synced { pendingDeletes.insert("saved_routes:\(route.id.uuidString.lowercased())"); savePending() }
        Task { await sync() }
    }

    // MARK: - Disk

    private var directory: URL {
        URL.documentsDirectory.appending(path: "Lapsy").appending(path: userKey)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func write<T: Encodable>(_ item: T, folder: String, id: UUID) {
        let dir = directory.appending(path: folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Self.encoder.encode(item) {
            try? data.write(to: dir.appending(path: "\(id.uuidString).json"), options: .atomic)
        }
    }

    private func remove(folder: String, id: UUID) {
        try? FileManager.default.removeItem(at: directory.appending(path: folder).appending(path: "\(id.uuidString).json"))
    }

    private func readAll<T: Decodable>(_ type: T.Type, folder: String) -> [T] {
        let dir = directory.appending(path: folder)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap {
            (try? Data(contentsOf: $0)).flatMap { try? Self.decoder.decode(T.self, from: $0) }
        }
    }

    private func load() {
        runs = readAll(SavedRun.self, folder: "runs").sorted { $0.startedAt > $1.startedAt }
        routes = readAll(SavedRoute.self, folder: "routes").sorted { $0.createdAt > $1.createdAt }
        let pending = (try? Data(contentsOf: directory.appending(path: "pending.json")))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        pendingDeletes = Set(pending)
    }

    private func savePending() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Array(pendingDeletes)) {
            try? data.write(to: directory.appending(path: "pending.json"), options: .atomic)
        }
    }

    // MARK: - Sync

    private struct RunRow: Codable {
        var id: UUID
        var activityId: String
        var startedAt: String
        var durationS: Double
        var distanceM: Double
        var energyKcal: Double
        var startName: String?
        var track: String
        var plannedPolyline: String?
        var plannedDistanceM: Double?
        var rating: Int?
    }

    private struct RouteRow: Codable {
        var id: UUID
        var name: String
        var activityId: String
        var startName: String?
        var distanceM: Double
        var ascentM: Double
        var durationS: Double
        var route: StoredRoute
        var createdAt: String?
    }

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        return isoFraction.date(from: text) ?? isoPlain.date(from: text)
    }

    private static let rowDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Pulls what is on the server, then pushes what only exists here. Safe to call often.
    func sync() async {
        guard let account, account.state == .signedIn, account.user != nil, !syncing else { return }
        syncing = true
        defer { syncing = false }
        let key = userKey
        do {
            try await pushDeletes(account)
            try await pullRuns(account)
            try await pullRoutes(account)
            try await pushRuns(account)
            try await pushRoutes(account)
            lastSyncError = nil
        } catch {
            if key == userKey { lastSyncError = (error as? APIError)?.message ?? "Couldn't back up right now." }
        }
    }

    private func pushDeletes(_ account: AccountStore) async throws {
        for item in pendingDeletes {
            let parts = item.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { pendingDeletes.remove(item); continue }
            _ = try await account.rest("rest/v1/\(parts[0])", method: "DELETE", query: ["id": "eq.\(parts[1])"])
            pendingDeletes.remove(item)
            savePending()
        }
    }

    private func pullRuns(_ account: AccountStore) async throws {
        let data = try await account.rest("rest/v1/runs", query: ["select": "*", "order": "started_at.desc", "limit": "500"])
        let rows = try Self.rowDecoder.decode([RunRow].self, from: data)
        let remoteIds = Set(rows.map(\.id))
        for row in rows {
            if let local = runs.first(where: { $0.id == row.id }), !local.synced { continue }   // local edit wins until pushed
            guard let started = Self.parse(row.startedAt) else { continue }
            let run = SavedRun(
                id: row.id, activityId: row.activityId, startedAt: started, durationS: row.durationS,
                distanceM: row.distanceM, energyKcal: row.energyKcal, startName: row.startName ?? "",
                track: row.track, plannedPolyline: row.plannedPolyline, plannedDistanceM: row.plannedDistanceM,
                rating: row.rating, synced: true
            )
            write(run, folder: "runs", id: run.id)
            runs = (runs.filter { $0.id != run.id } + [run]).sorted { $0.startedAt > $1.startedAt }
        }
        // Deleted on another device.
        if rows.count < 500 {
            for gone in runs where gone.synced && !remoteIds.contains(gone.id) {
                remove(folder: "runs", id: gone.id)
                runs.removeAll { $0.id == gone.id }
            }
        }
    }

    private func pullRoutes(_ account: AccountStore) async throws {
        let data = try await account.rest("rest/v1/saved_routes", query: ["select": "*", "order": "created_at.desc", "limit": "500"])
        let rows = try Self.rowDecoder.decode([RouteRow].self, from: data)
        let remoteIds = Set(rows.map(\.id))
        for row in rows {
            if let local = routes.first(where: { $0.id == row.id }), !local.synced { continue }
            let saved = SavedRoute(
                id: row.id, name: row.name, activityId: row.activityId, startName: row.startName ?? "",
                createdAt: Self.parse(row.createdAt) ?? Date(), route: row.route, synced: true
            )
            write(saved, folder: "routes", id: saved.id)
            routes = (routes.filter { $0.id != saved.id } + [saved]).sorted { $0.createdAt > $1.createdAt }
        }
        if rows.count < 500 {
            for gone in routes where gone.synced && !remoteIds.contains(gone.id) {
                remove(folder: "routes", id: gone.id)
                routes.removeAll { $0.id == gone.id }
            }
        }
    }

    private func pushRuns(_ account: AccountStore) async throws {
        for run in runs where !run.synced {
            let row = RunRow(
                id: run.id, activityId: run.activityId, startedAt: Self.isoPlain.string(from: run.startedAt),
                durationS: run.durationS, distanceM: run.distanceM, energyKcal: run.energyKcal,
                startName: run.startName, track: run.track, plannedPolyline: run.plannedPolyline,
                plannedDistanceM: run.plannedDistanceM, rating: run.rating
            )
            _ = try await account.rest(
                "rest/v1/runs", method: "POST", query: ["on_conflict": "id"], body: [row],
                headers: ["Prefer": "resolution=merge-duplicates,return=minimal"]
            )
            var done = run
            done.synced = true
            write(done, folder: "runs", id: done.id)
            if let i = runs.firstIndex(where: { $0.id == done.id }) { runs[i] = done }
        }
    }

    private func pushRoutes(_ account: AccountStore) async throws {
        for saved in routes where !saved.synced {
            let row = RouteRow(
                id: saved.id, name: saved.name, activityId: saved.activityId, startName: saved.startName,
                distanceM: saved.route.distanceM, ascentM: saved.route.ascentM, durationS: saved.route.durationS,
                route: saved.route, createdAt: Self.isoPlain.string(from: saved.createdAt)
            )
            _ = try await account.rest(
                "rest/v1/saved_routes", method: "POST", query: ["on_conflict": "id"], body: [row],
                headers: ["Prefer": "resolution=merge-duplicates,return=minimal"]
            )
            var done = saved
            done.synced = true
            write(done, folder: "routes", id: done.id)
            if let i = routes.firstIndex(where: { $0.id == done.id }) { routes[i] = done }
        }
    }
}
