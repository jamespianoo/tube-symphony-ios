import SwiftUI
import MapLibre

struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if let data = model.data {
                TubeMapView(model: model, data: data, active: visible && scenePhase == .active)
                    .ignoresSafeArea(edges: .top)
            } else if let err = model.loadError {
                ContentUnavailableView("The map data didn't load", systemImage: "exclamationmark.triangle", description: Text(err))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color("LaunchBackground"))
            }

            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    Button { model.mapBridge.controller?.recenter() } label: {
                        Image(systemName: "scope").font(.system(size: 17, weight: .semibold)).frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Show the whole network")
                }
                if model.settings.showDiagnostics { DiagnosticsCard() }
                MiniPlayer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .onAppear { visible = true; model.mapDidAppear() }
        .onDisappear { visible = false; model.mapDidDisappear() }
    }
}

struct TubeMapView: UIViewRepresentable {
    let model: AppModel
    let data: TubeData
    let active: Bool

    func makeCoordinator() -> MapController { MapController(model: model, data: data) }
    func makeUIView(context: Context) -> MLNMapView { context.coordinator.makeMapView() }
    func updateUIView(_ view: MLNMapView, context: Context) {
        context.coordinator.applySettings()
        context.coordinator.setActive(active)
    }
    static func dismantleUIView(_ view: MLNMapView, coordinator: MapController) { coordinator.teardown() }
}

/// Play/pause and the rendition, floating over the map.
struct MiniPlayer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let player = model.player
        HStack(spacing: 12) {
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            VStack(alignment: .leading, spacing: 2) {
                Text("Tube Symphony").font(.subheadline.weight(.semibold))
                Text(player.isPlaying ? (player.isBuffering ? "Buffering…" : "Live · \(KeySchedule.key().name)") : "Tap play to listen")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Mix", selection: Bindable(player).rendition) {
                ForEach(Rendition.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// What the clock and the loop are doing, for checking sync and cost on a device.
struct DiagnosticsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.mapStats, p = model.player
        VStack(alignment: .leading, spacing: 2) {
            Text("clock \(s.clock.rawValue)  ·  \(String(format: "%.1f", s.fps)) fps  ·  \(s.carriages) carriages  ·  \(model.trainCount) trains")
            Text("drawing \(String(format: "%.1f", s.renderLagS)) s behind London  ·  feed \(s.snapshotAgeS.map { String(format: "%.1f s old", $0) } ?? "—")")
            Text("audio \(p.clockState.rawValue)  ·  locks \(p.lockCount)  ·  anchor \(p.anchorOffsetMs.map { "\(Int($0)) ms" } ?? "—")  ·  behind \(p.behindLiveSeconds.map { String(format: "%.1f s", $0) } ?? "—")")
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}
