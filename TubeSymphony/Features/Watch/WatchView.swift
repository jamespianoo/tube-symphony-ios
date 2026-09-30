import SwiftUI

struct WatchView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        MacPage {
            MacWindow(title: "Watch", subtitle: "On YouTube") {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tube Symphony is broadcast live on YouTube around the clock: the whole network, with close-ups of stations as the trains arrive. Watch it on a television or share it with friends.")
                        .macType(.hero).foregroundStyle(Mac.dim).fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 16)
                    if let url = AppConfig.youTubeLiveURL {
                        Button { openURL(url) } label: {
                            HStack(spacing: 12) {
                                YouTubeMark()
                                Text("YouTube Livestream").macType(.button)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.mac(minHeight: 38))
                    } else {
                        // a tooltip's box (.mac-tip): white, an ink edge, Roboto Mono 10 bold
                        Text("The livestream link isn't set yet (AppConfig.youTubeLiveURL).")
                            .macType(.tooltip)
                            .foregroundStyle(Mac.cardInk)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Mac.rail)
                            .macEdge(.light)
                    }
                    MacSection(heading: "Sound") {
                        Text("YouTube plays its own sound, so the app's stream pauses while it plays.")
                            .macType(.hero).foregroundStyle(Mac.dim).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 18)
                }
            }
        }
    }
}

/// The YouTube mark in its own colours (drawer.css .settings-link-icon--youtube: 24 wide).
struct YouTubeMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(rgb: 0xFF0000))
            .frame(width: 24, height: 17)
            .overlay { MacIcon.view(.play, size: 14).foregroundStyle(.white) }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }
}
