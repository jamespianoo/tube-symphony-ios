import SwiftUI

/// The website's /audio page, in the app, to its CSS: one window with a coral
/// title bar, LIVE and the London clock, a 96 pt play button, the mix and the
/// sleep timer (plus the key and the output picker, in the same grammar); under
/// it, a way to the map and the credit.
struct ListenView: View {
    @Environment(AppModel.self) private var model
    @State private var key = KeySchedule.key()
    @State private var listeningSince: Date?
    @State private var sleepMinutes = 0
    @State private var showAbout = false

    private static let sleepChoices: [(Int, String)] = [
        (0, "Off"), (15, "15 min"), (30, "30 min"), (45, "45 min"),
        (60, "1 hour"), (90, "1½ hours"), (120, "2 hours"), (240, "4 hours"),
    ]

    var body: some View {
        let player = model.player
        MacPage {
            MacWindow(title: "Tube Symphony", subtitle: "Live from the Underground") {
                Button { showAbout = true } label: {
                    Text("?").macType(.question).frame(width: 32, height: 32)
                }
                .buttonStyle(.macSquareLight)
                .accessibilityLabel("About Tube Symphony")
            } content: {
                VStack(alignment: .leading, spacing: 0) {
                    // .top: margin-bottom 18
                    HStack(spacing: 10) {
                        MacLiveBadge(isOn: player.isPlaying)
                        Spacer(minLength: 0)
                        LondonClock()
                    }
                    .padding(.bottom, 18)

                    // .hero: margin-bottom 18 (collapses with the first .sec's 14)
                    VStack(spacing: 0) {
                        Text("Every train on the Underground plays a note as it arrives. The live mix, with nothing to look at.")
                            .macType(.hero)
                            .foregroundStyle(Mac.dim)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: MacType.hero.ch * 34)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 16)
                        Button { player.toggle() } label: {
                            MacIcon.view(player.isPlaying ? .pause : .play, size: 40).frame(width: 96, height: 96)
                        }
                        .buttonStyle(.mac(on: player.isPlaying, minHeight: 96, padding: 0))
                        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(status(player, now: ctx.date)).macType(.status).foregroundStyle(Mac.dim)
                        }
                        .frame(minHeight: 16)
                        .padding(.top, 14)
                        .accessibilityAddTraits(.updatesFrequently)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 18)

                    VStack(spacing: 14) {
                        MacSection(heading: "Mix") {
                            HStack(spacing: 10) {
                                ForEach(Rendition.allCases) { r in
                                    Button { player.rendition = r } label: {
                                        Text(r.title).macType(.button).frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.mac(on: player.rendition == r))
                                    .accessibilityAddTraits(player.rendition == r ? .isSelected : [])
                                }
                            }
                            note("Relax plays softer sounds, for falling asleep.")
                        }

                        MacSection(heading: "Key") {
                            Text(key.name).macType(.key).foregroundStyle(Mac.ink)
                            note("The key moves one step round the circle of fifths every hour. Major by day, minor from 5 pm.")
                        }

                        MacSection(heading: "Sleep Timer") {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                                ForEach(Self.sleepChoices, id: \.0) { mins, label in
                                    Button { setSleep(mins) } label: {
                                        Text(label).macType(.gridButton).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.mac(on: sleepMinutes == mins, padding: 4))
                                    .accessibilityAddTraits(sleepMinutes == mins ? .isSelected : [])
                                }
                            }
                            if let end = player.sleepEndsAt {
                                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                    Text("Stops in \(Self.clock(end.timeIntervalSince(ctx.date)))")
                                        .macType(.countdown)
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 10).padding(.vertical, 8)
                                        .background(Mac.on)
                                        .macEdge()
                                }
                                .padding(.top, 12)
                            }
                            note("Switches to the Relax mix, then fades out over the last 30 seconds.")
                        }

                        MacSection(heading: "Play On") {
                            HStack(spacing: 12) {
                                Text("AirPlay or Bluetooth. It keeps playing with the screen locked.")
                                    .macType(.hero).foregroundStyle(Mac.dim)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                MacRoutePicker()
                            }
                        }
                    }
                }
            }

            // .foot: margin-top 18, gap 14
            VStack(spacing: 14) {
                Button { model.tab = .map } label: {
                    HStack(spacing: 10) {
                        MacIcon.view(.mapGrid, size: 20)
                        Text("Open the Map").macType(.button)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.mac)
                MacCredit(showAbout: $showAbout)
            }
        }
        .fullScreenCover(isPresented: $showAbout) { AboutModal() }
        .onChange(of: player.isPlaying, initial: true) { _, playing in listeningSince = playing ? Date() : nil }
        .onChange(of: player.sleepEndsAt) { _, end in if end == nil { sleepMinutes = 0 } }
        .task {
            // Keep the key current while this tab is open.
            while !Task.isCancelled {
                key = KeySchedule.key()
                try? await Task.sleep(for: .seconds(max(1, KeySchedule.nextChange().timeIntervalSinceNow)))
            }
        }
    }

    private func note(_ s: String) -> some View {
        Text(s).macType(.hero).foregroundStyle(Mac.dim).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
    }

    private func setSleep(_ mins: Int) {
        sleepMinutes = mins
        if mins > 0 { model.player.startSleep(minutes: mins) } else { model.player.cancelSleep() }
    }

    private func status(_ p: StreamPlayer, now: Date) -> String {
        guard p.isPlaying else { return "Press play" }
        if p.isBuffering { return "Buffering…" }
        guard let since = listeningSince else { return "Live" }
        return "Live · listening \(Self.clock(now.timeIntervalSince(since)))"
    }

    /// 4:05, or 1:04:05 (the page's fmt()).
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds)), h = s / 3600, m = (s / 60) % 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

/// /audio .clock: "LONDON" in Chicago 11, 8 pt, then the time in Roboto Mono 13.
struct LondonClock: View {
    private static let format: Date.FormatStyle = {
        var f = Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "en_GB"),
                                 timeZone: TimeZone(identifier: "Europe/London")!)
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            HStack(spacing: 8) {
                Text("London").macType(.clockLabel).foregroundStyle(Mac.dim)
                Text(ctx.date.formatted(Self.format)).macType(.clockValue).foregroundStyle(Mac.ink)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
