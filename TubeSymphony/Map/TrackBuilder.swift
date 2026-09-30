import Foundation
import CoreLocation

/// The drawn tracks: tracks.json from tools/export-tube-data, where each line's
/// routes were deduplicated so shared trunk is drawn once (the glow would stack
/// brighter otherwise). Format: [[lineKey, [[lng, lat], …]], …].
enum TrackBuilder {
    struct Track {
        let line: String
        let coordinates: [CLLocationCoordinate2D]
    }

    static func load(from bundle: Bundle = .main) throws -> [Track] {
        guard let url = bundle.url(forResource: "tracks", withExtension: "json") else { throw TubeData.LoadError.missing("tracks.json") }
        guard let runs = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[Any]] else {
            throw TubeData.LoadError.corrupt("tracks.json")
        }
        return runs.compactMap { run in
            guard run.count == 2, let line = run[0] as? String, let pts = run[1] as? [[Double]] else { return nil }
            let coords = pts.compactMap { $0.count == 2 ? CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) : nil }
            return coords.count >= 2 ? Track(line: line, coordinates: coords) : nil
        }
    }
}
