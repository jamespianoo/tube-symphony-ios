import Foundation

/// Where the app finds the live piece. Everything streamed comes from the same
/// server the website runs on; nothing here needs a new endpoint.
enum AppConfig {
    static let origin = URL(string: "https://tubesymphony.com")!

    /// The Schedule, rewritten once a second by services/schedule: every train's
    /// place as a distance along its route, the last minute of arrivals (with the
    /// note each one played) and the next 15 s of predicted ones. Over HTTP it is
    /// gzip-compressed, which the 10 Hz WebSocket is not — about a hundredth of the
    /// data the website pulls on a phone.
    static var scheduleURL: URL { origin.appending(path: "map-assets/schedule/schedule.json") }
    static let schedulePollInterval: Duration = .seconds(1)

    /// How far behind the Schedule the map draws when no audio is playing. The feed
    /// arrives once a second, so this must cover one interval plus network jitter.
    static let networkRenderDelayMs: Double = 2500

    /// The mixed audio (services/audio), as HLS: AAC in half-second fMP4 segments.
    static func playlistURL(_ r: Rendition) -> URL { origin.appending(path: "map-assets/hls/\(r.rawValue)/stream.m3u8") }
    /// Which Schedule instant each rendition carries (services/audio/hls-anchor.js).
    static func anchorURL(_ r: Rendition) -> URL { origin.appending(path: "map-assets/hls/\(r.rawValue)/anchor.json") }

    static var statusURL: URL { origin.appending(path: "api/status.php") }
    static var audioOnlyURL: URL { origin.appending(path: "audio/") }

    /// The YouTube broadcast. The website reads this from config/youtube.php on the
    /// server, which is not in the repository; paste the same URL here.
    static let youTubeLiveURL: URL? = nil
}

enum Rendition: String, CaseIterable, Identifiable {
    case normal, relax
    var id: String { rawValue }
    var title: String { self == .normal ? "Normal" : "Relax" }
}

struct LinkItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let url: URL
}

/// The More tab's links. Add the other Labs projects to `labs`.
enum Links {
    static let tubeSymphony: [LinkItem] = [
        LinkItem(title: "Tube Symphony on the web", subtitle: "tubesymphony.com", systemImage: "safari", url: AppConfig.origin),
        LinkItem(title: "Audio only", subtitle: "The listening page", systemImage: "headphones", url: AppConfig.audioOnlyURL),
    ]
    static let labs: [LinkItem] = [
        LinkItem(title: "James Beckwith", subtitle: "jamesbeckwith.com", systemImage: "music.note", url: URL(string: "https://www.jamesbeckwith.com")!),
        // LinkItem(title: "Another project", subtitle: "What it is", systemImage: "sparkles", url: URL(string: "https://…")!),
    ]
}
