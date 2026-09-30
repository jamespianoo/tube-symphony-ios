import Foundation
import Observation
import UIKit

/// The app's one shared state: the bundled network, the live feed, the fleet it
/// fills, the audio stream, and which clock the map is drawn on.
@MainActor
@Observable
final class AppModel {
    private(set) var data: TubeData?
    private(set) var loadError: String?
    let player = StreamPlayer()
    let settings = AppSettings()
    let lineStatus = LineStatusStore()
    var tab: AppTab = .map

    @ObservationIgnored let fleet = FleetModel()
    @ObservationIgnored private let feed = ScheduleFeed()
    @ObservationIgnored private var mapWatchers = 0

    /// For the diagnostics overlay (updated about once a second).
    private(set) var trainCount = 0
    var mapStats = MapStats()
    @ObservationIgnored let mapBridge = MapBridge()

    init() {
        feed.onSnapshot = { [weak self] snap, receipt in
            guard let self else { return }
            self.fleet.ingest(snap, receiptWall: receipt)
            self.trainCount = self.fleet.vehicles.count
        }
        Task.detached(priority: .userInitiated) {
            do {
                let d = try TubeData.loadBundled()
                await MainActor.run { self.data = d }
            } catch {
                await MainActor.run { self.loadError = "\(error)" }
            }
        }
    }

    // MARK: - feed lifetime

    /// The feed runs only while a map is on screen and the app is in front: the
    /// audio carries its own notes, so a phone in a pocket fetches nothing but sound.
    func mapDidAppear() { mapWatchers += 1; feed.start() }
    func mapDidDisappear() { mapWatchers = max(0, mapWatchers - 1); if mapWatchers == 0 { feed.stop() } }
    func sceneBecameActive() { if mapWatchers > 0 { feed.start() } }
    func sceneWentToBackground() { feed.stop() }

    // MARK: - the drawn instant

    enum ClockSource: String { case audio = "audio", network = "network", none = "—" }

    /// The Schedule instant the map should show now. On the audio clock this is what
    /// the listener is hearing, so every blip lands on its note; otherwise it is live
    /// minus enough to interpolate between once-a-second samples.
    func renderTime() -> (t: Double, source: ClockSource)? {
        if player.isPlaying {
            if let s = player.scheduleNow() { return (s, .audio) }
            return nil   // draw nothing rather than draw live and leap back when the audio locks
        }
        let wall = Date().timeIntervalSince1970 * 1000
        guard let now = fleet.networkScheduleNow(wallMs: wall) else { return nil }
        return (now - AppConfig.networkRenderDelayMs, .network)
    }
}

/// User settings, kept in UserDefaults.
@Observable
final class AppSettings {
    var showStationNames: Bool { didSet { save() } }
    var showBlips: Bool { didSet { save() } }
    var smoothMotion: Bool { didSet { save() } }
    var showDiagnostics: Bool { didSet { save() } }

    private let d = UserDefaults.standard
    private static let defaults: [String: Bool] = ["showStationNames": true, "showBlips": true, "smoothMotion": false, "showDiagnostics": false]
    init() {
        d.register(defaults: Self.defaults)
        showStationNames = d.bool(forKey: "showStationNames")
        showBlips = d.bool(forKey: "showBlips")
        smoothMotion = d.bool(forKey: "smoothMotion")
        showDiagnostics = d.bool(forKey: "showDiagnostics")
    }
    /// The drawer's "Reset To Defaults".
    func reset() {
        showStationNames = Self.defaults["showStationNames"]!
        showBlips = Self.defaults["showBlips"]!
        smoothMotion = Self.defaults["smoothMotion"]!
        showDiagnostics = Self.defaults["showDiagnostics"]!
    }
    private func save() {
        d.set(showStationNames, forKey: "showStationNames")
        d.set(showBlips, forKey: "showBlips")
        d.set(smoothMotion, forKey: "smoothMotion")
        d.set(showDiagnostics, forKey: "showDiagnostics")
    }
}
