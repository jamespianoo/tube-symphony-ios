import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import Observation

/// The server-mixed audio, played by AVPlayer straight from the HLS renditions,
/// and the clock that keeps the map on the sound (js/stream/hls-audio.js).
///
/// The phone decodes AAC in hardware and does nothing else, so this is the
/// coolest way to listen. It also plays in the background and on the lock screen,
/// which a browser tab cannot be relied on to do.
///
/// THE CLOCK — which Schedule instant is leaving the speaker right now?
///
///     scheduleInstant = playingDate + anchor.offsetMs
///
/// playingDate is the stream's programme date at the playhead. As on the web's
/// native-HLS path it is measured physically: to play live the player must hold
/// audio up to the live edge, so what it holds ahead of the playhead is its
/// distance behind the edge, and the edge's date comes from the playlist.
/// AVPlayerItem.currentDate() is the fallback (Safari's equivalent put the map
/// seconds off the sound in 2026-09 testing). The clock runs on currentTime and is
/// only steered by the formula, read twice a second.
@MainActor
@Observable
final class StreamPlayer {
    struct Anchor: Decodable {
        let offsetMs: Double
        let edgeScheduleEpochMs: Double?
        let updatedAt: String?
    }

    enum ClockState: String { case idle, estimate, locked, coasting }

    // Published state
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    var rendition: Rendition = .normal { didSet { if oldValue != rendition { switchRendition() } } }
    private(set) var clockState: ClockState = .idle
    private(set) var behindLiveSeconds: Double?
    private(set) var anchorOffsetMs: Double?
    private(set) var lockCount = 0
    private(set) var sleepEndsAt: Date?

    // Constants from hls-audio.js
    private let snapMs = 2000.0
    private let encoderLagMs = 1500.0
    private let nativeEdgeLagMs = 1000.0
    private let liveOffsetS = 10.0

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var anchors: [Rendition: Anchor] = [:]
    @ObservationIgnored private var edge: (pdtMs: Double, fetchedAt: Double)?
    @ObservationIgnored private var clockBase: (ct: Double, sched: Double)?
    @ObservationIgnored private var lastLocked: (sched: Double, at: Double)?
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private var observers: [NSKeyValueObservation] = []
    @ObservationIgnored private var sleepTimer: Timer?
    @ObservationIgnored private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        cfg.timeoutIntervalForRequest = 5
        return URLSession(configuration: cfg)
    }()

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        observers.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            let status = p.timeControlStatus
            Task { @MainActor in
                self?.isBuffering = status == .waitingToPlayAtSpecifiedRate
            }
        })
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo
            Task { @MainActor in self?.handleInterruption(info) }
        }
        setUpRemoteCommands()
    }

    // MARK: - transport

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        activateSession()
        if player.currentItem == nil { loadItem() }
        player.play()
        isPlaying = true
        startTimers()
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        clockBase = nil
        clockState = lastLocked == nil ? .idle : .coasting
        stopTimers()
        updateNowPlaying()
    }

    private func loadItem() {
        let item = AVPlayerItem(url: AppConfig.playlistURL(rendition))
        item.preferredForwardBufferDuration = liveOffsetS
        item.automaticallyPreservesTimeOffsetFromLive = true
        item.configuredTimeOffsetFromLive = CMTime(seconds: liveOffsetS, preferredTimescale: 1000)
        player.replaceCurrentItem(with: item)
        clockBase = nil
        edge = nil
    }

    private func switchRendition() {
        guard player.currentItem != nil else { return }
        // Both renditions carry the same Schedule instants, so the clock survives a
        // switch; the website crossfades two elements, this simply swaps.
        loadItem()
        if isPlaying { player.play() }
        Task { await pollAnchors(); await pollEdge() }
        updateNowPlaying()
    }

    private func activateSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try? s.setActive(true)
    }

    private func handleInterruption(_ info: [AnyHashable: Any]?) {
        guard let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began { isPlaying = false; clockBase = nil; stopTimers() }
        else if let o = info?[AVAudioSessionInterruptionOptionKey] as? UInt,
                AVAudioSession.InterruptionOptions(rawValue: o).contains(.shouldResume) { play() }
    }

    // MARK: - sleep

    /// Sleep: switch to the relax mix, then fade out and stop after `minutes`.
    func startSleep(minutes: Int) {
        rendition = .relax
        if !isPlaying { play() }
        sleepEndsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimer?.invalidate()
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sleepTick() }
        }
    }

    func cancelSleep() {
        sleepTimer?.invalidate(); sleepTimer = nil
        sleepEndsAt = nil
        player.volume = 1
    }

    private func sleepTick() {
        guard let end = sleepEndsAt else { return }
        let left = end.timeIntervalSinceNow
        if left <= 0 { pause(); cancelSleep(); return }
        player.volume = Float(min(1, left / 30))   // fade over the last 30 s
    }

    // MARK: - clock

    /// The Schedule instant being heard, or nil before anything is known.
    func scheduleNow() -> Double? {
        let nowMono = CACurrentMediaTime() * 1000
        if let base = clockBase, isPlaying {
            let ct = player.currentTime().seconds
            if ct.isFinite {
                let s = base.sched + (ct - base.ct) * 1000
                lastLocked = (s, nowMono)
                return s
            }
        }
        if let l = lastLocked { return l.sched + (nowMono - l.at) }
        return estimateScheduleNow()
    }

    /// What the anchor's live edge implies the player is hearing, before it has said.
    private func estimateScheduleNow() -> Double? {
        guard let a = anchors[rendition], let edgeSched = a.edgeScheduleEpochMs,
              let updated = a.updatedAt, let at = Self.isoDate(updated) else { return nil }
        let age = Date().timeIntervalSince(at) * 1000
        guard age >= 0, age < 120_000 else { return nil }
        return edgeSched + age - liveOffsetS * 1000 - encoderLagMs
    }

    private func bufferedAheadMs() -> Double? {
        guard let item = player.currentItem else { return nil }
        let ct = item.currentTime().seconds
        guard ct.isFinite else { return nil }
        for v in item.loadedTimeRanges {
            let r = v.timeRangeValue
            let start = r.start.seconds, end = (r.start + r.duration).seconds
            if start <= ct + 0.5 && end >= ct { return max(0, (end - ct) * 1000) }
        }
        return nil
    }

    private func playingDateMs() -> Double? {
        if let e = edge, let ahead = bufferedAheadMs() {
            let since = min(4000, max(0, CACurrentMediaTime() * 1000 - e.fetchedAt))
            return e.pdtMs + since + nativeEdgeLagMs - ahead - 250
        }
        if let d = player.currentItem?.currentDate() { return d.timeIntervalSince1970 * 1000 }
        return nil
    }

    private func updateClock() {
        guard isPlaying, let item = player.currentItem, item.status == .readyToPlay,
              let anchor = anchors[rendition], let pd = playingDateMs() else {
            if isPlaying { clockState = lastLocked == nil ? .estimate : .coasting }
            return
        }
        anchorOffsetMs = anchor.offsetMs
        let ct = player.currentTime().seconds
        guard ct.isFinite else { return }
        let target = pd + anchor.offsetMs
        behindLiveSeconds = (Date().timeIntervalSince1970 * 1000 - target) / 1000
        guard let base = clockBase else { clockBase = (ct, target); lockCount += 1; clockState = .locked; return }
        let err = target - (base.sched + (ct - base.ct) * 1000)
        if abs(err) > snapMs { clockBase = (ct, target); lockCount += 1 }      // a seek or a discontinuity
        else { clockBase = (base.ct, base.sched + err * 0.05) }                // ease, never jump
        clockState = .locked
    }

    // MARK: - polling (only while playing)

    private func startTimers() {
        guard timers.isEmpty else { return }
        let add = { (interval: TimeInterval, body: @escaping @MainActor (StreamPlayer) async -> Void) in
            let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in if let self { await body(self) } }
            }
            t.tolerance = interval * 0.1
            self.timers.append(t)
        }
        add(0.5) { $0.updateClock() }
        add(1.5) { await $0.pollEdge() }
        add(5.0) { await $0.pollAnchors() }
        Task { await pollAnchors(); await pollEdge() }
    }

    private func stopTimers() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
    }

    private func pollAnchors() async {
        let r = rendition
        var comps = URLComponents(url: AppConfig.anchorURL(r), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970 * 1000)))]
        guard let result = try? await session.data(from: comps.url!),
              let a = try? JSONDecoder().decode(Anchor.self, from: result.0) else { return }
        anchors[r] = a
    }

    /// The live edge's programme date: last EXT-X-PROGRAM-DATE-TIME plus its segment.
    private func pollEdge() async {
        var comps = URLComponents(url: AppConfig.playlistURL(rendition), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970 * 1000)))]
        guard let result = try? await session.data(from: comps.url!),
              let text = String(data: result.0, encoding: .utf8) else { return }
        if let pdt = Self.liveEdgeMs(playlist: text) { edge = (pdt, CACurrentMediaTime() * 1000) }
    }

    nonisolated static func liveEdgeMs(playlist: String) -> Double? {
        var pdt: Double?, dur: Double?
        for raw in playlist.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXT-X-PROGRAM-DATE-TIME:") {
                if let d = isoDate(String(line.dropFirst("#EXT-X-PROGRAM-DATE-TIME:".count))) { pdt = d.timeIntervalSince1970 * 1000 }
            } else if line.hasPrefix("#EXTINF:") {
                let v = line.dropFirst("#EXTINF:".count).split(separator: ",").first.map(String.init) ?? ""
                dur = Double(v)
            }
        }
        guard let p = pdt else { return nil }
        return p + (dur ?? 0) * 1000
    }

    nonisolated static func isoDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    // MARK: - lock screen

    private func setUpRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.play() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        c.nextTrackCommand.isEnabled = false
        c.previousTrackCommand.isEnabled = false
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "Tube Symphony",
            MPMediaItemPropertyArtist: "Live from the London Underground",
            MPMediaItemPropertyAlbumTitle: rendition == .relax ? "Relax" : "Live",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let img = UIImage(named: "NowPlayingArtwork") {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
