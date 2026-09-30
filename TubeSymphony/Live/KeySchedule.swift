import Foundation

/// The piece's key clock (js/audio/params/key-schedule.js): the shared tonic moves
/// one step round the circle of fifths every hour, major from 05:00 to 16:59 and
/// minor from 17:00 to 04:59, London time. 05:00 is F major, 17:00 F minor.
enum KeySchedule {
    static let circle = ["F", "C", "G", "D", "A", "E", "B", "G♭", "D♭", "A♭", "E♭", "B♭"]

    struct Key: Equatable {
        let root: String
        let isMinor: Bool
        var name: String { "\(root) \(isMinor ? "minor" : "major")" }
    }

    static func key(at date: Date = Date()) -> Key {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        let h = cal.component(.hour, from: date)
        let slot = (h - 5 + 24) % 24
        return Key(root: circle[slot % 12], isMinor: slot >= 12)
    }

    /// When the key next changes (the top of the next hour).
    static func nextChange(after date: Date = Date()) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        let start = cal.dateInterval(of: .hour, for: date)!.start
        return start.addingTimeInterval(3600)
    }
}
