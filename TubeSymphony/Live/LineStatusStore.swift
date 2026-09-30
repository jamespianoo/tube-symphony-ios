import Foundation
import Observation

/// TfL line status through the website's own cache (api/status.php →
/// data/tfl-status.json.gz): per line, the worst current status.
@MainActor
@Observable
final class LineStatusStore {
    struct Status: Decodable {
        let severity: Int
        let desc: String
        let reason: String
        /// TfL's 10 is "Good Service"; 18 and 19 are informational.
        var isGood: Bool { severity == 10 || severity == 18 || severity == 19 }
    }

    private(set) var statuses: [String: Status] = [:]
    private(set) var updated: Date?
    private(set) var error: String?

    func refresh() async {
        do {
            let (data, resp) = try await URLSession.shared.data(from: AppConfig.statusURL)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { error = "Line status is unavailable just now."; return }
            statuses = Self.parse(data)
            updated = Date()
            error = nil
        } catch {
            self.error = "Couldn't reach the line status."
        }
    }

    /// Accepts the slim map `{ lineId: { severity, desc, reason } }`, or the same
    /// under a `lines` key.
    nonisolated static func parse(_ data: Data) -> [String: Status] {
        let dec = JSONDecoder()
        if let m = try? dec.decode([String: Status].self, from: data) { return m }
        struct Wrapped: Decodable { let lines: [String: Status] }
        if let w = try? dec.decode(Wrapped.self, from: data) { return w.lines }
        // Tolerate extra non-status keys.
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: Status] = [:]
        for (k, v) in obj {
            guard let d = v as? [String: Any], let sev = (d["severity"] as? NSNumber)?.intValue else { continue }
            out[k] = Status(severity: sev, desc: d["desc"] as? String ?? "", reason: d["reason"] as? String ?? "")
        }
        return out
    }
}
