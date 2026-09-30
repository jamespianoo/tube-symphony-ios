import Foundation

/// One arrival as the Schedule publishes it. `note.step` is the arpeggiator step the
/// server chose (seeded on line, train, station and London day), so a synth on the
/// phone would play the same note the stream carries.
struct ScheduleArrival {
    let id: Int
    let line: String
    let route: String
    let trainId: String
    let stationId: String
    let stationIdx: Int
    let t: Double          // Schedule ms
    let noteStep: Int?
    let predicted: Bool
}

/// [line, routeId, dist, dwelling, vehicleKey, dir] — the broadcaster's sample shape.
struct VehicleRow {
    let line: String
    let route: String
    let dist: Double
    let dwelling: Bool
    let key: String
    let dir: Int?
}

struct ScheduleSnapshot {
    let epoch: Double
    let trains: [VehicleRow]
    let arrivals: [ScheduleArrival]
}

/// Polls schedule.json once a second while something is watching the map.
///
/// The website's phones take the WebSocket instead: the whole fleet as JSON ten
/// times a second, uncompressed (252 KB/s, measured in docs/part2/time-lapse.md).
/// The file is the same data at a tenth of the rate, and gzip over HTTP takes it
/// to roughly a tenth of the size again. The map interpolates between samples
/// either way.
final class ScheduleFeed {
    private var task: Task<Void, Never>?
    private let session: URLSession
    /// Called on the main actor with each new snapshot and the wall-clock ms it arrived.
    var onSnapshot: (@MainActor (ScheduleSnapshot, Double) -> Void)?
    private var lastEpoch: Double = 0

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        cfg.timeoutIntervalForRequest = 4
        cfg.httpAdditionalHeaders = ["Accept-Encoding": "gzip, br"]
        session = URLSession(configuration: cfg)
    }

    var isRunning: Bool { task != nil }

    func start() {
        guard task == nil else { return }
        task = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(for: AppConfig.schedulePollInterval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func pollOnce() async {
        do {
            let (data, response) = try await session.data(from: AppConfig.scheduleURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let receipt = Date().timeIntervalSince1970 * 1000
            guard let snap = Self.parse(data), snap.epoch > lastEpoch else { return }
            lastEpoch = snap.epoch
            if let cb = onSnapshot { await cb(snap, receipt) }
        } catch {
            // Offline or a blip in the network: the map coasts on what it has.
        }
    }

    /// Hand-parsed rather than Codable: the rows are heterogeneous arrays.
    static func parse(_ data: Data) -> ScheduleSnapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let epoch = (obj["epoch"] as? NSNumber)?.doubleValue else { return nil }
        var trains: [VehicleRow] = []
        if let rows = obj["trains"] as? [[Any]] {
            trains.reserveCapacity(rows.count)
            for row in rows {
                guard row.count >= 5,
                      let line = row[0] as? String,
                      let route = row[1] as? String,
                      let dist = (row[2] as? NSNumber)?.doubleValue else { continue }
                let phase = (row[3] as? NSNumber)?.intValue ?? 0
                let key: String
                if let s = row[4] as? String { key = s } else if let n = row[4] as? NSNumber { key = n.stringValue } else { key = "" }
                var dir: Int? = nil
                if row.count >= 6, let d = (row[5] as? NSNumber)?.intValue, d == 1 || d == -1 { dir = d }
                trains.append(VehicleRow(line: line, route: route, dist: dist, dwelling: phase == 1, key: key, dir: dir))
            }
        }
        var arrivals: [ScheduleArrival] = []
        if let list = obj["arrivals"] as? [[String: Any]] {
            for a in list {
                guard let line = a["line"] as? String, let t = (a["t"] as? NSNumber)?.doubleValue else { continue }
                let note = a["note"] as? [String: Any]
                arrivals.append(ScheduleArrival(
                    id: (a["id"] as? NSNumber)?.intValue ?? -1,
                    line: line,
                    route: a["route"] as? String ?? "",
                    trainId: a["trainId"] as? String ?? "",
                    stationId: a["stationId"] as? String ?? "",
                    stationIdx: (a["stationIdx"] as? NSNumber)?.intValue ?? -1,
                    t: t,
                    noteStep: (note?["step"] as? NSNumber)?.intValue,
                    predicted: a["predicted"] as? Bool ?? false))
            }
        }
        return ScheduleSnapshot(epoch: epoch, trains: trains, arrivals: arrivals)
    }
}
