import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            List {
                Section("Map") {
                    Toggle("Station names", isOn: $settings.showStationNames)
                    Toggle("Blips when a note plays", isOn: $settings.showBlips)
                    Toggle(isOn: $settings.smoothMotion) {
                        VStack(alignment: .leading) {
                            Text("Smoother motion")
                            Text("Draws trains at 30 fps. Uses more battery and runs warmer.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Clock diagnostics", isOn: $settings.showDiagnostics)
                }
                Section("Tube Symphony") {
                    ForEach(Links.tubeSymphony) { LinkRow(item: $0) }
                    NavigationLink("About") { AboutView() }
                    NavigationLink("Credits") { CreditsView() }
                }
                Section("Labs") {
                    ForEach(Links.labs) { LinkRow(item: $0) }
                }
                Section {
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("More")
        }
    }
}

struct LinkRow: View {
    let item: LinkItem
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(item.url) } label: {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage).frame(width: 24).foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text(item.title).foregroundStyle(.primary)
                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("London is music, tube the orchestra.").font(.title3.weight(.semibold))
                Text("Tube Symphony is a map of the London Underground that turns the network into music and art. As a train stops at a station, a tone plays and a blip shows on the map. Each tube line has its own unique sound. There are over 350 stations in London. The result: a symphony of sound.")
                Text("This piece is live 24/7, and will never sound the same twice. Sparse trains in the early morning gradually build into an explosion of sound and colour at rush hour. Then, after the rush, the day service operates - a continuous, drone-like composition as trains arrive at their stations. This leads to the evening rush hour, a torrent of colour and noise during the busiest time on the network. Then the evening service, where the texture thins and has more room to breathe. At night we enter an ethereal, liminal space, as the service winds down and stray trains pass through the network in the middle of the night. Feel free to fall asleep to it.")
                Text("The audio is powered by the Ganymede Synth Engine, a web based synthesiser I have developed for audio-visual projects. Each line has its own arpeggiator, built on a distinct key, scale, and note range, which fires whenever a train reaches a station - turning the movement of the network into an orchestra. This composition will continue forever, driven by live TfL data powering the movement of trains on the map.")
                Text("For the geeks: this isn't a perfect rendering of the network. The TfL API itself is quite patchy - trains can lag, skip, or briefly vanish from the feed. The DLR in particular has rough data. All this affects the vibe of the piece, so some things have been smoothed out to aid the musicality of it. Don't plan your journey using this, but please, enjoy your city in motion.")
                Text("This piece is created by me, James Beckwith. I am a musician based in London.")
            }
            .padding(20)
        }
        .navigationTitle("About")
    }
}

struct CreditsView: View {
    private let credits: [(String, String, String)] = [
        ("Map data", "© OpenStreetMap contributors", "https://www.openstreetmap.org/copyright"),
        ("Vector tiles", "OpenMapTiles", "https://openmaptiles.org/"),
        ("Map rendering", "MapLibre Native", "https://maplibre.org/"),
        ("Train data", "Transport for London", "https://tfl.gov.uk/"),
        ("Rail data", "National Rail Darwin", "https://raildata.org.uk/"),
        ("Weather", "Open-Meteo", "https://open-meteo.com/"),
        ("Audio streaming", "FFmpeg and HLS", "https://ffmpeg.org/"),
    ]
    @Environment(\.openURL) private var openURL

    var body: some View {
        List(credits, id: \.0) { c in
            Button { openURL(URL(string: c.2)!) } label: {
                VStack(alignment: .leading) {
                    Text(c.0).font(.caption).foregroundStyle(.secondary)
                    Text(c.1).foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("Credits")
    }
}
