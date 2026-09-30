import SwiftUI
import AVKit

struct ListenView: View {
    @Environment(AppModel.self) private var model
    @State private var key = KeySchedule.key()

    var body: some View {
        let player = model.player
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 6) {
                        Text("Now playing in").font(.subheadline).foregroundStyle(.secondary)
                        Text(key.name).font(.system(size: 40, weight: .bold, design: .serif))
                        Text("The key moves one step round the circle of fifths every hour. Major by day, minor from 5 pm.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)

                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 88))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                    if player.isBuffering { ProgressView("Buffering") }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mix").font(.headline)
                        Picker("Mix", selection: Bindable(player).rendition) {
                            ForEach(Rendition.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text("Relax plays softer sounds, for falling asleep.").font(.footnote).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sleep").font(.headline)
                        if let end = player.sleepEndsAt {
                            HStack {
                                Text("Fading out at \(end.formatted(date: .omitted, time: .shortened))")
                                Spacer()
                                Button("Cancel") { player.cancelSleep() }
                            }
                        } else {
                            HStack {
                                ForEach([15, 30, 60, 90], id: \.self) { m in
                                    Button("\(m) min") { player.startSleep(minutes: m) }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Text("Play on").font(.headline)
                        Spacer()
                        RoutePicker().frame(width: 44, height: 44)
                    }

                    Text("The sound is mixed live on the Tube Symphony server and streamed, so the phone only has to decode it. It keeps playing with the screen locked.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Listen")
        }
        .task {
            // Keep the key current while this tab is open.
            while !Task.isCancelled {
                key = KeySchedule.key()
                try? await Task.sleep(for: .seconds(max(1, KeySchedule.nextChange().timeIntervalSinceNow)))
            }
        }
    }
}

/// AirPlay and Bluetooth output picker.
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.activeTintColor = .systemTeal
        v.tintColor = .label
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
