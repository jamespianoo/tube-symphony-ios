import Foundation
import MapLibre
import QuartzCore
import UIKit

/// Owns the MLNMapView and the loop that moves the trains.
///
/// Heat budget, in order of what it saves over the website:
///  - Trains are one symbol layer fed from a single shape source; stations, names
///    and note ripples are MapLibre layers. Nothing is a view or DOM element.
///  - The train loop runs at 10 fps zoomed out, 15 fps close in (8 in Low Power
///    Mode), 30 only if "Smoother motion" is on. It stops whenever the map is off
///    screen or the app is in the background.
///  - The map itself renders at up to 30 fps (MLNMapView's low-power setting), not
///    the 120 Hz a ProMotion screen would otherwise ask for.
///  - Only carriages inside the view (plus a margin) are sent to the map.
@MainActor
final class MapController: NSObject, MLNMapViewDelegate {
    private let model: AppModel
    private let data: TubeData
    private let zs: ZoomScale
    private(set) var mapView: MLNMapView!
    private var trainsSource: MLNShapeSource?
    private var blipsSource: MLNShapeSource?
    private var link: CADisplayLink?
    private var active = false
    private var currentFps: Float = 0

    private struct Blip { let coord: CLLocationCoordinate2D; let color: String; let start: CFTimeInterval }
    private var blips: [Blip] = []
    private static let blipDuration: CFTimeInterval = 3.5     // css/style.css .blip ripple 3.5s ease-out

    // Diagnostics, pushed to the model about once a second.
    private var ticks = 0
    private var lastStatsAt: CFTimeInterval = 0
    private var lastFeatureCount = 0
    private var lastClock: AppModel.ClockSource = .none

    init(model: AppModel, data: TubeData) {
        self.model = model
        self.data = data
        self.zs = ZoomScale(c: data.scale)
        super.init()
    }

    func makeMapView() -> MLNMapView {
        let v = MLNMapView(frame: .zero, styleURL: data.basemapStyleURL)
        v.delegate = self
        v.logoView.isHidden = true
        v.preferredFramesPerSecond = model.settings.smoothMotion ? .default : .lowPower
        v.minimumZoomLevel = data.scale.view.minZoom
        v.maximumZoomLevel = data.scale.mapMaxZoom
        v.isRotateEnabled = true
        v.isPitchEnabled = true
        let c = data.scale.view.startCenter
        v.setCenter(CLLocationCoordinate2D(latitude: c[1], longitude: c[0]), zoomLevel: data.scale.view.startZoom, animated: false)
        mapView = v
        model.mapBridge.controller = self
        return v
    }

    func teardown() {
        link?.invalidate(); link = nil
        mapView?.delegate = nil
    }

    // MARK: - lifetime

    func setActive(_ on: Bool) {
        active = on
        if on { startLink() } else { link?.isPaused = true }
    }

    private func startLink() {
        if link == nil {
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }
        link?.isPaused = !(active && trainsSource != nil)
        updateFrameRate()
    }

    private func desiredFps() -> Float {
        if model.settings.smoothMotion { return 30 }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return 8 }
        return (mapView?.zoomLevel ?? 0) >= 13 ? 15 : 10
    }

    private func updateFrameRate() {
        let fps = desiredFps()
        guard fps != currentFps, let link else { return }
        currentFps = fps
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(8, fps), maximum: fps, preferred: fps)
    }

    func applySettings() {
        guard let v = mapView else { return }
        v.preferredFramesPerSecond = model.settings.smoothMotion ? .default : .lowPower
        v.style?.layer(withIdentifier: MapStyleLayers.labelsLayer)?.isVisible = model.settings.showStationNames
        v.style?.layer(withIdentifier: MapStyleLayers.blipsLayer)?.isVisible = model.settings.showBlips
        updateFrameRate()
    }

    func recenter() {
        let c = data.scale.view.startCenter
        mapView.setCenter(CLLocationCoordinate2D(latitude: c[1], longitude: c[0]),
                          zoomLevel: data.scale.view.startZoom, direction: 0, animated: true)
    }

    // MARK: - MLNMapViewDelegate

    nonisolated func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        MainActor.assumeIsolated {
            let (t, b) = MapStyleLayers.install(on: style, data: data)
            trainsSource = t
            blipsSource = b
            applySettings()
            startLink()
        }
    }

    /// Keep the camera over London (the website's maxViewport for phones).
    nonisolated func mapView(_ mapView: MLNMapView, shouldChangeFrom oldCamera: MLNMapCamera, to newCamera: MLNMapCamera) -> Bool {
        MainActor.assumeIsolated {
            let vp = data.scale.view.maxViewport
            let c = newCamera.centerCoordinate
            return c.longitude >= vp.sw[0] && c.longitude <= vp.ne[0] && c.latitude >= vp.sw[1] && c.latitude <= vp.ne[1]
        }
    }

    nonisolated func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
        MainActor.assumeIsolated { updateFrameRate() }
    }

    // MARK: - the loop

    @objc private func tick(_ link: CADisplayLink) {
        guard active, let trainsSource, let mapView, let rt = model.renderTime() else { return }
        let renderT = rt.t, clock = rt.source
        let now = CACurrentMediaTime()
        let zoom = mapView.zoomLevel

        // Notes whose moment has come become ripples at their platform.
        let due = model.fleet.takeDueArrivals(upTo: renderT)
        if model.settings.showBlips {
            for a in due {
                guard let r = data.route(a.line, a.route), let c = r.stationCoordinate(a.stationIdx),
                      let line = data.linesByKey[a.line] else { continue }
                blips.append(Blip(coord: c, color: line.color, start: now))
            }
        }

        // Carriages, culled to the view plus a margin.
        let b = mapView.visibleCoordinateBounds
        let padLat = (b.ne.latitude - b.sw.latitude) * 0.15, padLng = (b.ne.longitude - b.sw.longitude) * 0.15
        let minLat = b.sw.latitude - padLat, maxLat = b.ne.latitude + padLat
        let minLng = b.sw.longitude - padLng, maxLng = b.ne.longitude + padLng
        var features: [MLNPointFeature] = []
        features.reserveCapacity(1400)
        for pose in model.fleet.poses(at: renderT) {
            guard let route = data.route(pose.line, pose.route), let line = data.linesByKey[pose.line] else { continue }
            let total = route.totalLength
            let placeDist = total > 0 ? min(max(pose.dist, 0), total) : pose.dist
            let centre = route.coordinate(at: placeDist)
            guard centre.latitude >= minLat, centre.latitude <= maxLat, centre.longitude >= minLng, centre.longitude <= maxLng else { continue }
            // positionTrainCarriages: centred on the chainage, one spacing apart.
            let count = line.carriageCount
            let centreIndex = Double(count - 1) / 2
            let spacing = zs.carriageSpacingMetres(line, lat: centre.latitude, zoom: zoom)
            let chord = pose.line == "dlr" ? 24.0 : 14.0
            for i in 0..<count {
                var d = placeDist + (centreIndex - Double(i)) * spacing
                if total > 0 { d = min(max(d, -RouteGeometry.extrapolateMaxM), total + RouteGeometry.extrapolateMaxM) }
                let f = MLNPointFeature()
                f.coordinate = route.coordinate(at: d)
                // The carriage image lies east–west; bearings are clockwise from north.
                f.attributes = ["img": "car-" + line.key, "rot": route.chordHeading(at: d, chordM: chord) - 90, "tpl": line.trainTemplate]
                features.append(f)
            }
        }
        trainsSource.shape = MLNShapeCollectionFeature(shapes: features)
        updateBlips(now: now, zoom: zoom)

        ticks += 1
        lastFeatureCount = features.count
        lastClock = clock
        if now - lastStatsAt >= 1 {
            model.mapStats = MapStats(fps: Double(ticks) / max(0.001, now - lastStatsAt), carriages: lastFeatureCount,
                                      clock: lastClock, renderLagS: (Date().timeIntervalSince1970 * 1000 - renderT) / 1000,
                                      snapshotAgeS: model.fleet.lastSnapshotWall > 0 ? Date().timeIntervalSince1970 - model.fleet.lastSnapshotWall / 1000 : nil)
            ticks = 0
            lastStatsAt = now
            updateFrameRate()
        }
    }

    private func updateBlips(now: CFTimeInterval, zoom: Double) {
        guard let blipsSource else { return }
        blips.removeAll { now - $0.start >= Self.blipDuration }
        if blips.isEmpty {
            if lastBlipCount > 0 { blipsSource.shape = nil; lastBlipCount = 0 }
            return
        }
        let scale = zs.blip(zoom)
        let dia = data.scale.blipRippleDiameterPx * scale, border = data.scale.blipRippleBorderPx * scale
        let features: [MLNPointFeature] = blips.map { bl in
            let t = min(1, (now - bl.start) / Self.blipDuration)
            let p = 1 - pow(1 - t, 2.2)                        // ≈ CSS ease-out
            let opacity = p < 0.5 ? 1 - 0.3 * p : 0.85 * (1 - (p - 0.5) / 0.5)
            let f = MLNPointFeature()
            f.coordinate = bl.coord
            f.attributes = ["r": dia * p / 2, "w": max(0, border * (1 - p)), "o": opacity, "color": bl.color]
            return f
        }
        blipsSource.shape = MLNShapeCollectionFeature(shapes: features)
        lastBlipCount = features.count
    }
    private var lastBlipCount = 0
}

struct MapStats {
    var fps: Double = 0
    var carriages = 0
    var clock: AppModel.ClockSource = .none
    var renderLagS: Double = 0
    var snapshotAgeS: Double?
}

/// Lets SwiftUI buttons reach the map without owning it.
final class MapBridge {
    weak var controller: MapController?
}
