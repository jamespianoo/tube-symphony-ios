import Foundation
import Observation

/// TfL line status: per line, the worst current status. First through the
/// website's own cache (api/status.php → data/tfl-status.json.gz); while the site
/// sits behind its password (it answers 401), straight from TfL's open API, whose
/// line ids are the app's line keys.
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
    /// Where the last statuses came from, for the footnote.
    private(set) var source = "TfL"

    func refresh() async {
        if let s = await fetch(AppConfig.statusURL, parse: Self.parse) {
            statuses = s; source = "TfL via Tube Symphony"
        } else if let s = await fetch(AppConfig.tflStatusURL, parse: Self.parseTfL) {
            statuses = s; source = "TfL"
        } else {
            error = statuses.isEmpty ? "Line status is unavailable just now." : "Couldn't refresh the line status."
            return
        }
        updated = Date()
        error = nil
    }

    private func fetch(_ url: URL, parse: (Data) -> [String: Status]) async -> [String: Status]? {
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let s = parse(data)
        return s.isEmpty ? nil : s
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

    /// TfL's `/Line/Mode/…/Status`: an array of lines, each with its statuses.
    /// The first one that isn't good is the one shown (TfL lists the most
    /// important first); otherwise the first.
    nonisolated static func parseTfL(_ data: Data) -> [String: Status] {
        struct Line: Decodable {
            struct S: Decodable { let statusSeverity: Int; let statusSeverityDescription: String; let reason: String? }
            let id: String
            let lineStatuses: [S]
        }
        guard let lines = try? JSONDecoder().decode([Line].self, from: data) else { return [:] }
        var out: [String: Status] = [:]
        for l in lines {
            let all = l.lineStatuses.map { Status(severity: $0.statusSeverity, desc: $0.statusSeverityDescription, reason: $0.reason ?? "") }
            if let s = all.first(where: { !$0.isGood }) ?? all.first { out[l.id] = s }
        }
        return out
    }
}
