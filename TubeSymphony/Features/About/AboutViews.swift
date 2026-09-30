import SwiftUI

/// A popup window (/audio .scrim + .modal): the page dimmed flat (rgba(23,24,26,.62)),
/// a light card at most 560 wide and min(82 %, 760) tall with a 1 px ink edge and
/// a 3 px ink shadow, a coral bar (padding 12 14) with a square light close button.
struct MacModal<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear.contentShape(Rectangle()).onTapGesture { dismiss() }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        MacTitle(title: title, subtitle: subtitle)
                        Spacer(minLength: 0)
                        Button { dismiss() } label: {
                            MacIcon.view(.close, size: 18).frame(width: 32, height: 32)
                        }
                        .buttonStyle(.macSquareLight)
                        .accessibilityLabel("Close")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Mac.coral)
                    .overlay(alignment: .bottom) { Rectangle().fill(Mac.cardInk).frame(height: 1) }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) { content() }
                            .padding(.horizontal, 18)                          // .modal-body: 16px 18px 18px
                            .padding(.top, 16)
                            .padding(.bottom, 18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .tint(Mac.coral)
                }
                .frame(maxWidth: 560)
                .frame(maxHeight: min(geo.size.height * 0.82, 760))
                .fixedSize(horizontal: false, vertical: true)
                .background(Mac.card)
                .foregroundStyle(Mac.cardInk)
                .macEdge(edge: Mac.ink, shadow: Mac.ink, lift: 3)
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .presentationBackground(Mac.desk.opacity(0.62))
    }
}

/// The map's About text (includes/about-panel.php), as /audio shows it.
struct AboutModal: View {
    var body: some View {
        MacModal(title: "About Tube Symphony", subtitle: "London is music, tube the orchestra.") {
            ForEach(Array(AboutText.paragraphs.enumerated()), id: \.offset) { i, p in
                Text(p).macType(.modalP).fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, i == AboutText.paragraphs.count - 1 ? 0 : 14)   // .modal-body p: margin 0 0 14px
            }
        }
    }
}

enum AboutText {
    static let paragraphs: [AttributedString] = [
        "Tube Symphony is a map of the London Underground that turns the network into music and art. As a train stops at a station, a tone plays and a blip shows on the map. Each tube line has its own unique sound. There are over 350 stations in London. The result: a symphony of sound.",
        "The experience is simple: open the map, watch the trains move, and let the sound build on its own. You can show or hide different lines, follow trains, see the departures at your nearest station, and experience the city in motion. With Spatial audio you can hear what's on your screen, and with Relax Mode softer sounds are played to help with falling asleep.",
        "This piece is live 24/7, and will never sound the same twice. Sparse trains in the early morning gradually build into an explosion of sound and colour at rush hour. Then, after the rush, the day service operates - a continuous, drone-like composition as trains arrive at their stations. This leads to the evening rush hour, a torrent of colour and noise during the busiest time on the network. Then the evening service, where the texture thins and has more room to breathe. At night we enter an ethereal, liminal space, as the service winds down and stray trains pass through the network in the middle of the night. Feel free to fall asleep to it.",
        "The audio is powered by the Ganymede Synth Engine, a web based synthesiser I have developed for audio-visual projects. Each line has its own arpeggiator, built on a distinct key, scale, and note range, which fires whenever a train reaches a station - turning the movement of the network into an orchestra. This composition will continue forever, driven by live TfL data powering the movement of trains on the map.",
        "For the geeks: this isn't a perfect rendering of the network. The TfL API itself is quite patchy - trains can lag, skip, or briefly vanish from the feed. The DLR in particular has rough data. All this affects the vibe of the piece, so some things have been smoothed out to aid the musicality of it. Don't plan your journey using this, but please, enjoy your city in motion.",
    ].map { AttributedString($0) } + [
        (try? AttributedString(markdown: "This piece is created by me, [James Beckwith](https://www.jamesbeckwith.com). I am a musician based in London.")) ?? "",
    ]
}

/// The map's Credits panel (includes/credits-panel.php): an intro, then sections
/// (Johnston 13, .08em, capitals; margin-top 6) over disc lists (indent 1.15em,
/// 8 apart), every line Johnston 15 / 1.55, and a note at 13 in the dim ink. The
/// body's items sit 14 apart (.about-panel-body gap).
struct CreditsModal: View {
    private struct Section: Identifiable { let title: String; let items: [String]; var id: String { title } }
    private let intro = "Tube Symphony is built from live public data and open tools. Thank you to everyone who makes these materials available."
    private let sections: [Section] = [
        Section(title: "Map", items: [
            "[MapTiler](https://www.maptiler.com/) - Dataviz Dark map style",
            "[OpenMapTiles](https://openmaptiles.org/) - vector tile schema and tools, © OpenMapTiles",
            "[MapLibre Native](https://maplibre.org/) - open-source map renderer",
            "[OpenStreetMap](https://www.openstreetmap.org/copyright) - map data © OpenStreetMap contributors",
        ]),
        Section(title: "Live transport data", items: [
            "[Transport for London](https://tfl.gov.uk/) - Unified API (arrivals, line status) and TrackerNet signalling for Tube lines",
            "[National Rail Darwin](https://raildata.org.uk/) (via Rail Data Marketplace) - live departure boards used to corroborate Elizabeth line and London Overground",
            "London Underground, Overground, Elizabeth line, and DLR network information powered by TfL open data",
        ]),
        Section(title: "Environment", items: [
            "[Open-Meteo](https://open-meteo.com/) - live weather for the London sky",
        ]),
        Section(title: "Streaming & runtime", items: [
            "[FFmpeg](https://ffmpeg.org/) and [HLS](https://developer.apple.com/streaming/) - audio stream delivery",
        ]),
        Section(title: "Sound", items: [
            "Ganymede Synth Engine - custom web synthesiser by [James Beckwith](https://www.jamesbeckwith.com)",
        ]),
        Section(title: "Typefaces", items: [
            "ChicagoFLF, [Fraunces](https://github.com/undercasetype/Fraunces) (SIL Open Font License) and [Roboto Mono](https://github.com/googlefonts/RobotoMono) (Apache 2.0)",
        ]),
    ]
    private let note = "This is an artwork, not a journey planner. Feed accuracy varies - especially on DLR and National Rail-backed lines. Line colours and network identity remain trademarks of Transport for London."

    var body: some View {
        MacModal(title: "Credits", subtitle: "With Thanks") {
            VStack(alignment: .leading, spacing: 14) {
                Text(intro).macType(.aboutText).fixedSize(horizontal: false, vertical: true)
                ForEach(sections) { s in
                    Text(s.title).macType(.aboutSection).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(s.items, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 0) {
                                Text("•").macType(.aboutText).frame(width: 15 * 1.15, alignment: .leading)
                                Text((try? AttributedString(markdown: item)) ?? AttributedString(item))
                                    .macType(.aboutText).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                Text(note).macType(.aboutNote).foregroundStyle(Mac.cardDim).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }
}

/// /audio .credit: "Created by James Beckwith © 2026 · About", Johnston 13 in the
/// dim ink, the name and About in coral.
struct MacCredit: View {
    @Binding var showAbout: Bool
    var color: Color = Mac.dim
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 0) {
            Text("Created by ").foregroundStyle(color)
            Button("James Beckwith") { openURL(URL(string: "https://www.jamesbeckwith.com")!) }.foregroundStyle(Mac.coral)
            Text(" © 2026 · ").foregroundStyle(color)
            Button("About") { showAbout = true }.foregroundStyle(Mac.coral)
        }
        .buttonStyle(.plain)
        .macType(.credit)
        .frame(maxWidth: .infinity)
    }
}
