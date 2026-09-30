import Foundation

/// Where every train is at a given Schedule instant: a port of the parts of
/// js/stream/remote-driver.js the phone needs. Samples are kept in Schedule time,
/// so the map can be drawn at whatever instant the listener is hearing: live
/// minus a little when nothing is playing, or the audio stream's own instant
/// (12–15 s behind) when it is.
final class FleetModel {
    struct Sample {
        let t: Double
        let dist: Double
        let dwelling: Bool
        let route: String
        let dir: Int?
    }

    final class Vehicle {
        let key: String
        let line: String
        var route: String
        var samples: [Sample] = []
        var cursor = 1
        var lastSeenWall: Double = 0
        var dir: Int?
        init(key: String, line: String, route: String) { self.key = key; self.line = line; self.route = route }
    }

    struct Pose {
        let line: String
        let route: String
        let dist: Double
        let dwelling: Bool
    }

    // RemoteDriver's constants.
    static let extrapolateCapMs = 2500.0
    static let vehicleTTLMs = 45_000.0
    static let sampleKeepMs = 3000.0          // behind the render time
    static let maxSamples = 120               // two minutes at 1 Hz
    static let clockWindow = 30               // snapshots the least delay is taken over
    static let arrivalLateDropMs = 1500.0

    private(set) var vehicles: [String: Vehicle] = [:]
    private var clockOffsets: [Double] = []
    private(set) var clockOffset: Double?     // wall ms − Schedule ms, least delay seen
    private var lastRenderT: Double?
    private var pendingArrivals: [ScheduleArrival] = []
    private var seenArrivalIds = Set<Int>()
    private(set) var lastSnapshotWall: Double = 0
    private(set) var lastEpoch: Double = 0

    // MARK: - clock

    /// Schedule ms "now" on the network clock (mapped through the least delay seen,
    /// as RemoteDriver.noteClock does, so two phones draw the same instant).
    func networkScheduleNow(wallMs: Double) -> Double? {
        guard let off = clockOffset else { return nil }
        return wallMs - off
    }

    private func noteClock(epoch: Double, receiptWall: Double) {
        clockOffsets.append(receiptWall - epoch)
        if clockOffsets.count > Self.clockWindow { clockOffsets.removeFirst(clockOffsets.count - Self.clockWindow) }
        let m = clockOffsets.min() ?? (receiptWall - epoch)
        if clockOffset == nil || m < clockOffset! - 150 { clockOffset = m }
    }

    // MARK: - ingest

    func ingest(_ snap: ScheduleSnapshot, receiptWall: Double) {
        noteClock(epoch: snap.epoch, receiptWall: receiptWall)
        lastSnapshotWall = receiptWall
        lastEpoch = snap.epoch
        for row in snap.trains {
            guard let key = Self.normalizeKey(line: row.line, key: row.key), row.dist.isFinite else { continue }
            let v: Vehicle
            if let existing = vehicles[key] { v = existing } else {
                v = Vehicle(key: key, line: row.line, route: row.route)
                vehicles[key] = v
            }
            push(v, Sample(t: snap.epoch, dist: row.dist, dwelling: row.dwelling, route: row.route, dir: row.dir))
            v.lastSeenWall = receiptWall
            if let d = row.dir { v.dir = d }
        }
        vehicles = vehicles.filter { receiptWall - $0.value.lastSeenWall <= Self.vehicleTTLMs }

        for a in snap.arrivals where !a.predicted && a.id >= 0 {
            guard !seenArrivalIds.contains(a.id) else { continue }
            seenArrivalIds.insert(a.id)
            pendingArrivals.append(a)
        }
        if seenArrivalIds.count > 5000 { seenArrivalIds = Set(pendingArrivals.map(\.id)) }
        pendingArrivals.sort { $0.t < $1.t }
    }

    private func push(_ v: Vehicle, _ s: Sample) {
        if let last = v.samples.last, s.t <= last.t { v.samples[v.samples.count - 1] = s; return }
        v.samples.append(s)
        if let rt = lastRenderT {
            var drop = 0
            while drop < v.samples.count - 2 && v.samples[drop + 1].t < rt - Self.sampleKeepMs { drop += 1 }
            if drop > 0 { v.samples.removeFirst(drop); v.cursor = max(1, v.cursor - drop) }
        }
        if v.samples.count > Self.maxSamples {
            let n = v.samples.count - Self.maxSamples
            v.samples.removeFirst(n); v.cursor = max(1, v.cursor - n)
        }
    }

    static func normalizeKey(line: String, key: String) -> String? {
        guard !key.isEmpty else { return nil }
        if !key.contains("|") { return line + "|" + key }
        if key.hasPrefix(line + "|") { return key }
        return nil
    }

    // MARK: - evaluate

    /// Every vehicle's pose at Schedule instant `renderT` (poseAt).
    func poses(at renderT: Double) -> [Pose] {
        lastRenderT = renderT
        var out: [Pose] = []
        out.reserveCapacity(vehicles.count)
        for v in vehicles.values {
            if let p = pose(v, renderT) { out.append(p) }
        }
        return out
    }

    private func pose(_ v: Vehicle, _ renderT: Double) -> Pose? {
        let s = v.samples
        guard let first = s.first else { return nil }
        let mk = { (x: Sample) in Pose(line: v.line, route: x.route, dist: x.dist, dwelling: x.dwelling) }
        if s.count == 1 || renderT <= first.t { return mk(first) }
        let last = s[s.count - 1]
        if renderT >= last.t {
            let prev = s[s.count - 2]
            if last.dwelling || prev.route != last.route { return mk(last) }
            let dt = max(1, last.t - prev.t)
            var vel = (last.dist - prev.dist) / dt
            if !vel.isFinite { vel = 0 }
            let age = min(renderT - last.t, Self.extrapolateCapMs)
            let damp = 1 - (age / Self.extrapolateCapMs) * 0.5   // decelerate a late packet rather than overshoot
            return Pose(line: v.line, route: last.route, dist: last.dist + vel * age * damp, dwelling: false)
        }
        var i = min(max(v.cursor, 1), s.count - 1)
        while i > 1 && s[i - 1].t >= renderT { i -= 1 }
        while i < s.count && s[i].t < renderT { i += 1 }
        v.cursor = i
        guard i < s.count else { return mk(last) }
        let a = s[i - 1], b = s[i]
        if a.route != b.route { return mk(renderT >= (a.t + b.t) * 0.5 ? b : a) }
        let u = (renderT - a.t) / max(1, b.t - a.t)
        return Pose(line: v.line, route: b.route, dist: a.dist + (b.dist - a.dist) * u, dwelling: u < 0.5 ? a.dwelling : b.dwelling)
    }

    /// Arrivals whose moment has come at `renderT`: the drawn train reaches the
    /// platform, and on the audio clock its note leaves the speaker. Arrivals the
    /// clock has jumped well past are dropped, not burst.
    func takeDueArrivals(upTo renderT: Double) -> [ScheduleArrival] {
        var due: [ScheduleArrival] = []
        while let first = pendingArrivals.first, first.t <= renderT {
            pendingArrivals.removeFirst()
            if renderT - first.t <= Self.arrivalLateDropMs { due.append(first) }
        }
        return due
    }

    func reset() {
        vehicles.removeAll()
        pendingArrivals.removeAll()
        clockOffsets.removeAll()
        clockOffset = nil
        lastRenderT = nil
    }
}
