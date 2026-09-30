import SwiftUI

struct WatchView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "play.tv")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                    Text("The YouTube broadcast")
                        .font(.title2.bold())
                    Text("Tube Symphony is broadcast live on YouTube around the clock: the whole network, with close-ups of stations as the trains arrive. Watch it on a television or share it with friends.")
                        .foregroundStyle(.secondary)
                    if let url = AppConfig.youTubeLiveURL {
                        Button { openURL(url) } label: {
                            Label("Watch on YouTube", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Label("The livestream link isn't set yet (AppConfig.youTubeLiveURL).", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("YouTube plays its own sound, so the app's stream pauses while it plays.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Watch")
        }
    }
}
