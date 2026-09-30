import Foundation
import MapLibre
import UIKit

/// The Tube Symphony layers on top of the basemap: tracks, blips, stations, trains
/// and station names. Everything is drawn by MapLibre on the GPU — no view per
/// station, no view per note — which is most of what makes this cooler than the
/// website, where each of those is a DOM element the browser lays out.
enum MapStyleLayers {
    static let tracksSource = "ts-tracks"
    static let stationsSource = "ts-stations"
    static let trainsSource = "ts-trains"
    static let blipsSource = "ts-blips"
    static let labelsLayer = "ts-station-labels"
    static let blipsLayer = "ts-blips"

    static func expr(_ json: Any) -> NSExpression { NSExpression(mglJSONObject: json) }
    static func const(_ v: Any) -> NSExpression { NSExpression(forConstantValue: v) }

    /// ["interpolate", ["linear"], ["zoom"], z, f(z), …]
    static func byZoom(_ scale: ZoomScale, _ f: (Double) -> Double) -> NSExpression {
        expr((["interpolate", ["linear"], ["zoom"]] as [Any]) + scale.stops(f))
    }

    static func install(on style: MLNStyle, data: TubeData) -> (trains: MLNShapeSource, blips: MLNShapeSource) {
        let zs = ZoomScale(c: data.scale)
        let view = data.scale.view

        // ---------------------------------------------------------- tracks
        let tracks: [MLNPolylineFeature] = data.tracks.map { t in
            var coords = t.coordinates
            let f = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
            let line = data.linesByKey[t.line]
            f.attributes = ["line": t.line, "color": line?.color ?? "#ffffff", "glow": line?.glowColor ?? "#ffffff"]
            return f
        }
        let trackSource = MLNShapeSource(identifier: tracksSource, shape: MLNShapeCollectionFeature(shapes: tracks), options: nil)
        style.addSource(trackSource)

        let glow = MLNLineStyleLayer(identifier: "ts-track-glow", source: trackSource)
        glow.lineColor = expr(["to-color", ["get", "glow"]])
        glow.lineWidth = byZoom(zs) { view.trackGlowWidth * zs.map($0) }
        glow.lineBlur = byZoom(zs) { view.trackGlowBlur * zs.map($0) }
        glow.lineOpacity = const(data.scale.trackGlowOpacity * 0.5)
        glow.lineCap = const("round"); glow.lineJoin = const("round")
        style.addLayer(glow)

        let casing = MLNLineStyleLayer(identifier: "ts-track-casing", source: trackSource)
        casing.lineColor = const(UIColor.white)
        casing.lineWidth = byZoom(zs) { view.lineWidthCasing * zs.map($0) }
        casing.lineCap = const("round"); casing.lineJoin = const("round")
        style.addLayer(casing)

        let core = MLNLineStyleLayer(identifier: "ts-track-core", source: trackSource)
        core.lineColor = expr(["to-color", ["get", "color"]])
        core.lineWidth = byZoom(zs) { view.lineWidthCore * zs.map($0) }
        core.lineCap = const("round"); core.lineJoin = const("round")
        style.addLayer(core)

        // ---------------------------------------------------------- blips (under stations and trains)
        let blipSource = MLNShapeSource(identifier: blipsSource, shape: nil, options: [.maximumZoomLevel: 14])
        style.addSource(blipSource)
        let blips = MLNCircleStyleLayer(identifier: blipsLayer, source: blipSource)
        blips.circleRadius = expr(["get", "r"])
        blips.circleOpacity = const(0)
        blips.circleStrokeWidth = expr(["get", "w"])
        blips.circleStrokeColor = expr(["to-color", ["get", "color"]])
        blips.circleStrokeOpacity = expr(["get", "o"])
        blips.circlePitchAlignment = const("map")
        style.addLayer(blips)

        // ---------------------------------------------------------- stations
        let stationFeatures: [MLNPointFeature] = data.stations.map { s in
            let f = MLNPointFeature()
            f.coordinate = s.coordinate
            f.attributes = ["name": s.name, "label": !s.suppressLabel]
            return f
        }
        let stationSource = MLNShapeSource(identifier: stationsSource, shape: MLNShapeCollectionFeature(shapes: stationFeatures), options: nil)
        style.addSource(stationSource)
        let dots = MLNCircleStyleLayer(identifier: "ts-station-dots", source: stationSource)
        dots.circleRadius = byZoom(zs) { view.stationDotSizePx / 2 * zs.map($0) }
        dots.circleColor = const(UIColor.white)
        dots.circleStrokeColor = const(UIColor(white: 0.08, alpha: 1))
        dots.circleStrokeWidth = byZoom(zs) { view.stationDotBorderPx * 0.6 * zs.map($0) }
        dots.circlePitchAlignment = const("map")
        style.addLayer(dots)

        // ---------------------------------------------------------- trains
        for line in data.lines { style.setImage(carriageImage(line), forName: "car-" + line.key) }
        let trainSource = MLNShapeSource(identifier: trainsSource, shape: nil, options: [.maximumZoomLevel: 14])
        style.addSource(trainSource)
        let trains = MLNSymbolStyleLayer(identifier: "ts-trains", source: trainSource)
        trains.iconImageName = expr(["get", "img"])
        trains.iconRotation = expr(["get", "rot"])
        trains.iconRotationAlignment = const("map")
        trains.iconPitchAlignment = const("map")
        trains.iconAllowsOverlap = const(true)
        trains.iconIgnoresPlacement = const(true)
        trains.iconScale = trainIconScale(data, zs)
        style.addLayer(trains)

        // ---------------------------------------------------------- station names
        let labels = MLNSymbolStyleLayer(identifier: labelsLayer, source: stationSource)
        labels.predicate = NSPredicate(format: "label == YES")
        labels.minimumZoomLevel = 12.5
        labels.text = expr(["get", "name"])
        labels.textFontNames = const(["Metropolis Semi Bold", "Noto Sans Bold"])
        labels.textFontSize = byZoom(zs) { z in
            let fontPx = view.stationLabelFontSizePx
            let zc = min(z, 18)
            let t = zc >= 18 ? 0 : (zc <= 15 ? 1 : (18 - zc) / 3)
            return max(9, fontPx * (zs.map(zc) + (2 / fontPx) * t))
        }
        labels.textColor = const(UIColor(white: 1, alpha: 0.92))
        labels.textHaloColor = const(UIColor(white: 0, alpha: 0.85))
        labels.textHaloWidth = const(1.2)
        labels.textVariableAnchor = const(["left", "right", "top", "bottom"])
        labels.textRadialOffset = const(0.9)
        labels.textOptional = const(true)
        style.addLayer(labels)

        return (trainSource, blipSource)
    }

    /// icon-size: getTrainScale × the fleet's zoom-out normalisation, per template.
    private static func trainIconScale(_ data: TubeData, _ zs: ZoomScale) -> NSExpression {
        var widths: [String: Double] = [:]
        for l in data.lines { widths[l.trainTemplate] = l.carriage.bodyW }
        let templates = widths.keys.sorted()
        var stops: [Any] = []
        var z = 6.0
        while z <= 21 {
            var match: [Any] = ["match", ["get", "tpl"]]
            for t in templates { match += [t, zs.train(z) * zs.fleetNorm(carriageBodyW: widths[t]!, zoom: z)] }
            match.append(zs.train(z))
            stops += [z, match]
            z += 0.5
        }
        return expr((["interpolate", ["linear"], ["zoom"]] as [Any]) + stops)
    }

    /// One carriage, drawn as the website draws it: the line's colour inside a white
    /// border (.train-carriage-casing), square corners, long side along the track.
    static func carriageImage(_ line: LineInfo) -> UIImage {
        let m = line.carriage
        let size = CGSize(width: m.outerW, height: m.outerH)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 3
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(hex: line.color).setFill()
            ctx.fill(CGRect(x: m.borderW, y: m.borderW, width: m.bodyW, height: m.bodyH))
        }
    }
}

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}
