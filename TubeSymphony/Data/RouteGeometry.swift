import Foundation
import CoreLocation

/// One route's curve, and the website's rules for placing a train on it
/// (getPositionAtDistance / coordAtPathDistance / pathChordHeadingDeg in
/// js/lines/trains.js and js/map/map.js). The Schedule sends a train as a
/// distance along its route; this turns that distance into a place and a heading.
final class RouteGeometry {
    let meta: RouteMeta
    let lng: [Double]
    let lat: [Double]
    let cum: [Double]

    /// PATH_EXTRAPOLATE_MAX_M: how far past either end a carriage may be drawn.
    static let extrapolateMaxM = 90.0

    var totalLength: Double { cum[cum.count - 1] }

    init(meta: RouteMeta, lng: [Double], lat: [Double], cum: [Double]) {
        self.meta = meta
        self.lng = lng
        self.lat = lat
        self.cum = cum
    }

    /// Index `lo` with cum[lo] <= d < cum[lo + 1].
    @inline(__always)
    private func segment(containing d: Double) -> Int {
        var lo = 0, hi = cum.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) >> 1
            if cum[mid] <= d { lo = mid } else { hi = mid }
        }
        return lo
    }

    func coordinate(at d: Double) -> CLLocationCoordinate2D {
        let last = cum.count - 1
        if d <= 0 {
            if d >= -1e-9 { return point(0) }
            return Self.extrapolate(from: point(1), through: point(0), metres: min(-d, Self.extrapolateMaxM))
        }
        if d >= totalLength {
            if d <= totalLength + 1e-9 { return point(last) }
            return Self.extrapolate(from: point(last - 1), through: point(last), metres: min(d - totalLength, Self.extrapolateMaxM))
        }
        let lo = segment(containing: d), hi = lo + 1
        let dLo = cum[lo], dHi = cum[hi]
        if dHi <= dLo { return point(lo) }
        let t = (d - dLo) / (dHi - dLo)
        return CLLocationCoordinate2D(latitude: lat[lo] + (lat[hi] - lat[lo]) * t,
                                      longitude: lng[lo] + (lng[hi] - lng[lo]) * t)
    }

    /// Heading from a chord centred on `d`, so corners blend across many points
    /// instead of snapping between segments (pathChordHeadingDeg).
    func chordHeading(at d: Double, chordM: Double) -> Double {
        let half = (chordM > 0 ? chordM : 10) * 0.5
        let a = coordinate(at: d - half), b = coordinate(at: d + half)
        if a.latitude == b.latitude && a.longitude == b.longitude { return segmentBearing(at: d) }
        return Self.bearing(a, b)
    }

    /// The bearing of the segment under `d` (getPositionAtDistance's `bearing`).
    func segmentBearing(at d: Double) -> Double {
        let last = cum.count - 1
        if d <= 0 { return Self.bearing(point(0), point(1)) }
        if d >= totalLength { return Self.bearing(point(last - 1), point(last)) }
        let lo = segment(containing: d)
        return Self.bearing(point(lo), point(min(lo + 1, last)))
    }

    @inline(__always)
    func point(_ i: Int) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat[i], longitude: lng[i])
    }

    func stationCoordinate(_ idx: Int) -> CLLocationCoordinate2D? {
        guard idx >= 0, idx < meta.stationCoords.count else { return nil }
        let c = meta.stationCoords[idx]
        return CLLocationCoordinate2D(latitude: c[1], longitude: c[0])
    }

    // MARK: - geodesy, as the website does it

    /// calculateBearing: initial great-circle bearing, degrees clockwise from north.
    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let r = Double.pi / 180
        let lon1 = a.longitude * r, lat1 = a.latitude * r
        let lon2 = b.longitude * r, lat2 = b.latitude * r
        let y = sin(lon2 - lon1) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lon2 - lon1)
        let deg = atan2(y, x) / r
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    static func distanceMetres(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let r = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * r, dLng = (b.longitude - a.longitude) * r
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.latitude * r) * cos(b.latitude * r) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * 6_371_000 * asin(min(1, sqrt(h)))
    }

    /// extrapolateAlongSegmentMeters: continue the line from `from` through `through`.
    static func extrapolate(from: CLLocationCoordinate2D, through: CLLocationCoordinate2D, metres: Double) -> CLLocationCoordinate2D {
        if abs(metres) < 1e-9 { return through }
        let seg = distanceMetres(from, through)
        if seg < 1e-4 { return CLLocationCoordinate2D(latitude: through.latitude + metres / 111_320, longitude: through.longitude) }
        let s = metres / seg
        return CLLocationCoordinate2D(latitude: through.latitude + (through.latitude - from.latitude) * s,
                                      longitude: through.longitude + (through.longitude - from.longitude) * s)
    }
}
