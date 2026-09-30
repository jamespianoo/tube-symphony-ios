import Foundation
import CoreLocation

// The network as the website draws it, exported from the website's own code by
// tools/export-tube-data and bundled. Nothing here is computed at launch beyond
// reading the files.

struct CarriageMetrics: Decodable {
    let bodyW: Double
    let bodyH: Double
    let borderW: Double
    let outerW: Double
    let outerH: Double
    let gapPx: Double
}

struct LineInfo: Decodable, Identifiable {
    let key: String
    let name: String
    let color: String
    let glowColor: String
    let centerStripe: Bool
    let trainTemplate: String
    let carriageCount: Int
    let carriage: CarriageMetrics
    var id: String { key }
}

struct StationInfo: Decodable, Identifiable {
    let id: String
    let name: String
    let coord: [Double]
    let lines: [String]
    let colors: [String]
    let suppressLabel: Bool
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0]) }
}

struct ViewProfile: Decodable {
    let startCenter: [Double]
    let startZoom: Double
    let minZoom: Double
    let maxViewport: Viewport
    let lineWidthCore: Double
    let lineWidthCasing: Double
    let trackGlowWidth: Double
    let trackGlowBlur: Double
    let stationDotSizePx: Double
    let stationDotBorderPx: Double
    let stationLabelFontSizePx: Double

    struct Viewport: Decodable { let sw: [Double]; let ne: [Double] }
}

/// The constants js/map/map.js sizes things by (getMapScale and friends), for the
/// phone view profile.
struct ScaleConstants: Decodable {
    let refZoom: Double
    let exponentIn: Double
    let exponentOut: Double
    let maxZoom: Double
    let mapMaxZoom: Double
    let train2dScale: Double
    let trainZoomOutShrink: Double
    let deepCarriageWidthPx: Double
    let blipRetain: Double
    let blipShrink: Double
    let blipRippleDiameterPx: Double
    let blipRippleBorderPx: Double
    let trackGlowOpacity: Double
    let view: ViewProfile
}

struct RouteMeta: Decodable {
    let line: String
    let id: String
    let offset: Int
    let count: Int
    let totalLength: Double
    let stationIds: [String?]
    let stationDistances: [Double]
    let stationCoords: [[Double]]
}

private struct RoutesFile: Decodable {
    let origin: [Double]
    let routes: [RouteMeta]
}

final class TubeData {
    let lines: [LineInfo]
    let linesByKey: [String: LineInfo]
    let routes: [String: RouteGeometry]      // "line|route"
    let stations: [StationInfo]
    let tracks: [TrackBuilder.Track]
    let scale: ScaleConstants
    let basemapStyleURL: URL

    static func routeKey(_ line: String, _ route: String) -> String { line + "|" + route }
    func route(_ line: String, _ route: String) -> RouteGeometry? { routes[Self.routeKey(line, route)] }

    init(lines: [LineInfo], routes: [String: RouteGeometry], stations: [StationInfo], tracks: [TrackBuilder.Track], scale: ScaleConstants, basemapStyleURL: URL) {
        self.lines = lines
        self.linesByKey = Dictionary(uniqueKeysWithValues: lines.map { ($0.key, $0) })
        self.routes = routes
        self.stations = stations
        self.tracks = tracks
        self.scale = scale
        self.basemapStyleURL = basemapStyleURL
    }

    enum LoadError: Error { case missing(String), corrupt(String) }

    static func loadBundled(from bundle: Bundle = .main) throws -> TubeData {
        func url(_ name: String, _ ext: String) throws -> URL {
            guard let u = bundle.url(forResource: name, withExtension: ext) else { throw LoadError.missing("\(name).\(ext)") }
            return u
        }
        let dec = JSONDecoder()
        let lines = try dec.decode([LineInfo].self, from: Data(contentsOf: url("lines", "json")))
        let stations = try dec.decode([StationInfo].self, from: Data(contentsOf: url("stations", "json")))
        let scale = try dec.decode(ScaleConstants.self, from: Data(contentsOf: url("scale", "json")))
        let file = try dec.decode(RoutesFile.self, from: Data(contentsOf: url("routes", "json")))
        let bin = try Data(contentsOf: url("routes", "bin"))
        guard file.origin.count == 2 else { throw LoadError.corrupt("routes.json origin") }
        let originLng = file.origin[0], originLat = file.origin[1]

        // routes.bin: little-endian Float32 triplets (lng − originLng, lat − originLat, cumulative metres).
        let floats: [Float32] = bin.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float32.self))
        }
        var routes: [String: RouteGeometry] = [:]
        for meta in file.routes {
            let start = meta.offset * 3, end = (meta.offset + meta.count) * 3
            guard end <= floats.count, meta.count >= 2 else { throw LoadError.corrupt("route \(meta.line)|\(meta.id)") }
            var lng = [Double](repeating: 0, count: meta.count)
            var lat = [Double](repeating: 0, count: meta.count)
            var cum = [Double](repeating: 0, count: meta.count)
            var j = 0
            for i in stride(from: start, to: end, by: 3) {
                lng[j] = Double(floats[i]) + originLng
                lat[j] = Double(floats[i + 1]) + originLat
                cum[j] = Double(floats[i + 2])
                j += 1
            }
            routes[routeKey(meta.line, meta.id)] = RouteGeometry(meta: meta, lng: lng, lat: lat, cum: cum)
        }
        let styleURL = try url("basemap-style", "json")
        let tracks = try TrackBuilder.load(from: bundle)
        return TubeData(lines: lines, routes: routes, stations: stations, tracks: tracks, scale: scale, basemapStyleURL: styleURL)
    }
}
