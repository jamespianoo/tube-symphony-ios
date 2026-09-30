import XCTest
import CoreLocation
@testable import TubeSymphony

final class GeometryTests: XCTestCase {
    struct Fixture: Decodable { let line: String; let route: String; let dist: Double; let lng: Double; let lat: Double }

    /// Trains land where the website puts them: fixtures are the website's own
    /// getPositionAtDistance answers, written by tools/export-tube-data.
    func testPlacementMatchesWebsite() throws {
        let data = try TubeData.loadBundled(from: .main)
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "geometry-fixtures", withExtension: "json"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        XCTAssertFalse(fixtures.isEmpty)
        for f in fixtures {
            let route = try XCTUnwrap(data.route(f.line, f.route), "\(f.line)|\(f.route)")
            let c = route.coordinate(at: f.dist)
            let err = RouteGeometry.distanceMetres(c, CLLocationCoordinate2D(latitude: f.lat, longitude: f.lng))
            XCTAssertLessThan(err, 1.0, "\(f.line)|\(f.route) @ \(f.dist)")
        }
    }

    func testBundleLoads() throws {
        let data = try TubeData.loadBundled(from: .main)
        XCTAssertEqual(data.lines.count, 19)
        XCTAssertGreaterThan(data.routes.count, 100)
        XCTAssertGreaterThan(data.stations.count, 400)
        XCTAssertFalse(data.tracks.isEmpty)
    }

    func testExtrapolatesPastTheEnds() throws {
        let data = try TubeData.loadBundled(from: .main)
        let r = try XCTUnwrap(data.routes.values.first)
        let end = r.coordinate(at: r.totalLength)
        let past = r.coordinate(at: r.totalLength + 50)
        XCTAssertEqual(RouteGeometry.distanceMetres(end, past), 50, accuracy: 1)
        let capped = r.coordinate(at: r.totalLength + 500)
        XCTAssertEqual(RouteGeometry.distanceMetres(end, capped), RouteGeometry.extrapolateMaxM, accuracy: 1)
    }
}

final class ScaleTests: XCTestCase {
    func testMapScaleIsOneAtReferenceZoom() throws {
        let data = try TubeData.loadBundled(from: .main)
        let zs = ZoomScale(c: data.scale)
        XCTAssertEqual(zs.map(data.scale.refZoom), 1, accuracy: 1e-9)
        XCTAssertLessThan(zs.train(10), zs.map(10))           // trains thin out when zoomed out
        XCTAssertEqual(zs.fleetNorm(carriageBodyW: data.scale.deepCarriageWidthPx, zoom: 9), 1)
    }
}

final class FeedTests: XCTestCase {
    func testParsesSchedule() throws {
        let json = """
        {"epoch":1000,"version":1,"trains":[["central","r1",1200.5,0,"123",1],["dlr","d2",50,1,"dlr|9",-1]],
         "arrivals":[{"id":7,"line":"central","route":"r1","trainId":"central|123","stationId":"940X","stationIdx":3,"t":900,"note":{"step":4,"order":"random"},"predicted":false},
                     {"line":"central","route":"r1","trainId":"x","stationId":"y","stationIdx":4,"t":1500,"note":null,"predicted":true}]}
        """
        let s = try XCTUnwrap(ScheduleFeed.parse(Data(json.utf8)))
        XCTAssertEqual(s.epoch, 1000)
        XCTAssertEqual(s.trains.count, 2)
        XCTAssertEqual(s.trains[0].dir, 1)
        XCTAssertTrue(s.trains[1].dwelling)
        XCTAssertEqual(s.arrivals.first?.noteStep, 4)
        XCTAssertTrue(s.arrivals[1].predicted)
    }

    func testInterpolatesBetweenSamples() {
        let fleet = FleetModel()
        let row = { (d: Double) in VehicleRow(line: "central", route: "r1", dist: d, dwelling: false, key: "123", dir: 1) }
        fleet.ingest(ScheduleSnapshot(epoch: 1000, trains: [row(100)], arrivals: []), receiptWall: 1050)
        fleet.ingest(ScheduleSnapshot(epoch: 2000, trains: [row(200)], arrivals: []), receiptWall: 2040)
        let p = fleet.poses(at: 1500)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p[0].dist, 150, accuracy: 1e-6)
        XCTAssertEqual(fleet.clockOffset, 50)                  // locked; re-locks only if 150 ms faster
        // Extrapolates a little past the newest sample, damped.
        XCTAssertGreaterThan(fleet.poses(at: 2500)[0].dist, 200)
    }

    func testArrivalsFireOnceAndLateOnesDrop() {
        let fleet = FleetModel()
        let a = { (id: Int, t: Double) in ScheduleArrival(id: id, line: "central", route: "r1", trainId: "central|1", stationId: "s", stationIdx: 0, t: t, noteStep: 1, predicted: false) }
        let snap = ScheduleSnapshot(epoch: 10_000, trains: [], arrivals: [a(1, 5000), a(2, 9000)])
        fleet.ingest(snap, receiptWall: 10_000)
        fleet.ingest(snap, receiptWall: 11_000)                 // same arrivals again: not queued twice
        let due = fleet.takeDueArrivals(upTo: 9500)
        XCTAssertEqual(due.map(\.id), [2])                      // 1 is 4.5 s late: dropped, not burst
        XCTAssertTrue(fleet.takeDueArrivals(upTo: 20_000).isEmpty)
    }
}

final class AudioClockTests: XCTestCase {
    func testLiveEdgeFromPlaylist() {
        let playlist = """
        #EXTM3U
        #EXT-X-TARGETDURATION:1
        #EXT-X-PROGRAM-DATE-TIME:2026-09-30T12:00:00.000Z
        #EXTINF:0.5,
        seg1.m4s
        #EXT-X-PROGRAM-DATE-TIME:2026-09-30T12:00:00.500Z
        #EXTINF:0.5,
        seg2.m4s
        """
        let edge = StreamPlayer.liveEdgeMs(playlist: playlist)
        let expected = StreamPlayer.isoDate("2026-09-30T12:00:01.000Z")!.timeIntervalSince1970 * 1000
        XCTAssertEqual(edge, expected)
    }

    func testKeySchedule() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        let at = { (h: Int) in cal.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: h, minute: 30))! }
        XCTAssertEqual(KeySchedule.key(at: at(5)).name, "F major")
        XCTAssertEqual(KeySchedule.key(at: at(6)).name, "C major")
        XCTAssertEqual(KeySchedule.key(at: at(17)).name, "F minor")
        XCTAssertEqual(KeySchedule.key(at: at(4)).name, "B♭ minor")
    }
}
