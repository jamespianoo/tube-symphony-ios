import SwiftUI
import MapLibre

struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if let data = model.data {
                TubeMapView(model: model, data: data, active: visible && scenePhase == .active,
                            showNames: model.settings.showStationNames, showBlips: model.settings.showBlips,
                            smooth: model.settings.smoothMotion)
                    .ignoresSafeArea(edges: .top)
            } else if let err = model.loadError {
                MacWindow(title: "Tube Symphony", subtitle: "The map didn't load") {
                    Text(err).macType(.hero).foregroundStyle(Mac.dim)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Mac.desk)
            } else {
                Text("Loading…").macType(.status).foregroundStyle(Mac.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Mac.desk)
            }

            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    Button { model.mapBridge.controller?.recenter() } label: {
                        Image(systemName: "scope").font(.system(size: 18, weight: .semibold)).frame(width: Mac.btn, height: Mac.btn)
                    }
                    .buttonStyle(.mac(padding: 0))
                    .accessibilityLabel("Show the whole network")
                }
                if model.settings.showDiagnostics { DiagnosticsCard() }
                MiniPlayer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .onAppear { visible = true; model.mapDidAppear() }
        .onDisappear { visible = false; model.mapDidDisappear() }
    }
}

struct TubeMapView: UIViewRepresentable {
    let model: AppModel
    let data: TubeData
    let active: Bool
    // Passed in (rather than read inside updateUIView) so a change re-runs updateUIView.
    let showNames: Bool
    let showBlips: Bool
    let smooth: Bool

    func makeCoordinator() -> MapController { MapController(model: model, data: data) }
    func makeUIView(context: Context) -> MLNMapView { context.coordinator.makeMapView() }
    func updateUIView(_ view: MLNMapView, context: Context) {
        context.coordinator.applySettings()
        context.coordinator.setActive(active)
    }
    static func dismantleUIView(_ view: MLNMapView, coordinator: MapController) { coordinator.teardown() }
}

/// Play/pause and the rendition, floating over the map: a small dark window.
struct MiniPlayer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let player = model.player
        HStack(spacing: 12) {
            Button { player.toggle() } label: {
                MacIcon.view(player.isPlaying ? .pause : .play, size: 22).frame(width: Mac.btn, height: Mac.btn)
            }
            .buttonStyle(.mac(on: player.isPlaying, minHeight: Mac.btn, padding: 0))
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            VStack(alignment: .leading, spacing: 4) {
                Text("Tube Symphony").macType(.secHead).foregroundStyle(Mac.coral).lineLimit(1)
                Text(status(player)).macType(.clockLabel).foregroundStyle(Mac.dim).lineLimit(1)
            }
            .minimumScaleFactor(0.8)
            Spacer(minLength: 4)

            HStack(spacing: 6) {
                ForEach(Rendition.allCases) { r in
                    Button { player.rendition = r } label: {
                        Text(r.title).macType(.option).lineLimit(1)
                    }
                    .buttonStyle(.mac(on: player.rendition == r, minHeight: 30, padding: 8, lift: 1))
                    .accessibilityAddTraits(player.rendition == r ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Mix")
        }
        .padding(10)
        .background(Mac.face)
        .macEdge(lift: 3)
    }

    private func status(_ p: StreamPlayer) -> String {
        guard p.isPlaying else { return "Press play" }
        return p.isBuffering ? "Buffering…" : "Live · \(KeySchedule.key().name)"
    }
}

/// What the clock and the loop are doing, for checking sync and cost on a device.
/// Built like the site's tooltips: white, an ink edge, the value face.
struct DiagnosticsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.mapStats, p = model.player
        VStack(alignment: .leading, spacing: 2) {
            Text("clock \(s.clock.rawValue)  ·  \(String(format: "%.1f", s.fps)) fps  ·  \(s.carriages) carriages  ·  \(model.trainCount) trains")
            Text("drawing \(String(format: "%.1f", s.renderLagS)) s behind London  ·  feed \(s.snapshotAgeS.map { String(format: "%.1f s old", $0) } ?? "—")")
            Text("audio \(p.clockState.rawValue)  ·  locks \(p.lockCount)  ·  anchor \(p.anchorOffsetMs.map { "\(Int($0)) ms" } ?? "—")  ·  behind \(p.behindLiveSeconds.map { String(format: "%.1f s", $0) } ?? "—")")
        }
        .macType(.tooltip)
        .foregroundStyle(Mac.cardInk)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Mac.rail)
        .macEdge(.light)
    }
}
