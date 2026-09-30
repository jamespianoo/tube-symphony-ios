import Foundation

/// How big things are drawn at a zoom: the website's getMapScale, getTrainScale,
/// getBlipScale, trainTemplateZoomNormFactor and getCarriageSpacingMeters
/// (js/map/map.js, js/lines/train-templates.js, js/lines/trains.js), with the
/// phone view profile's constants. MapLibre Native and MapLibre GL JS share the
/// 512-px tile convention, so zoom levels mean the same on both.
struct ZoomScale {
    let c: ScaleConstants

    /// getMapScale: soft growth around the reference zoom, 1:1 with the camera past maxZoom.
    func map(_ zoom: Double) -> Double {
        if zoom < c.refZoom { return pow(2, (zoom - c.refZoom) * c.exponentOut) }
        let softIn = { (z: Double) in pow(2, (z - c.refZoom) * c.exponentIn) }
        if zoom <= c.maxZoom { return softIn(zoom) }
        return softIn(c.maxZoom) * pow(2, zoom - c.maxZoom)
    }

    /// getTrainScale: trains thin out faster than tracks when zoomed out.
    func train(_ zoom: Double) -> Double {
        let s = map(zoom)
        let overall = c.train2dScale > 0 ? c.train2dScale : 1
        guard s < 1 else { return s * overall }
        let shrink = min(1, max(0, c.trainZoomOutShrink))
        return s * (1 - (1 - s) * shrink) * overall
    }

    /// getBlipScale.
    func blip(_ zoom: Double) -> Double {
        let s = map(zoom)
        if s >= 1 { return s }
        let out = 1 - s
        return s + out * c.blipRetain - out * c.blipShrink
    }

    /// trainTemplateZoomNormFactor: longer fleets shrink toward deep-tube length when zoomed out.
    func fleetNorm(carriageBodyW: Double, zoom: Double) -> Double {
        let deepW = c.deepCarriageWidthPx
        guard carriageBodyW > deepW * 1.02 else { return 1 }
        let t = min(1, max(0, map(zoom)))
        return (deepW / carriageBodyW) * (1 - t) + t
    }

    /// metersPerPixel in js/map/map.js.
    static func metresPerPixel(lat: Double, zoom: Double) -> Double {
        78271.5170 * cos(lat * .pi / 180) / pow(2, zoom)
    }

    /// getCarriageSpacingMeters: carriages sit a fixed number of screen pixels apart.
    func carriageSpacingMetres(_ line: LineInfo, lat: Double, zoom: Double) -> Double {
        let spacingPx = line.carriage.outerW + line.carriage.gapPx
        return spacingPx * train(zoom) * fleetNorm(carriageBodyW: line.carriage.bodyW, zoom: zoom)
            * Self.metresPerPixel(lat: lat, zoom: zoom)
    }

    /// Sample a scale function as MapLibre interpolate stops (zoom → value).
    func stops(from: Double = 6, to: Double = 21, step: Double = 0.5, _ f: (Double) -> Double) -> [Any] {
        var out: [Any] = []
        var z = from
        while z <= to + 1e-9 { out.append(z); out.append(f(z)); z += step }
        return out
    }
}
