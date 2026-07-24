import Foundation

/// Korean reset-time phrasing used across the popover.
enum TimeText {
    /// "3시간 8분 후 초기화" / "12분 후 초기화" from a future date.
    static func resetsIn(_ date: Date?, now: Date = Date()) -> String {
        guard let date, date > now else { return "곧 초기화" }
        let secs = Int(date.timeIntervalSince(now))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "\(h)시간 \(m)분 후 초기화" }
        return "\(m)분 후 초기화"
    }

    /// "일요일 21:59 초기화" — absolute weekday + time.
    static func resetsAt(_ date: Date?) -> String {
        guard let date else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "EEEE HH:mm"
        return "\(fmt.string(from: date)) 초기화"
    }

    /// "14:40" — compact absolute reset clock for the menu bar (5h window).
    static func clockShort(_ date: Date?) -> String? {
        guard let date else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }

    /// "일 21:59" — compact weekday + reset clock for the menu bar (weekly window).
    static func weekdayClockShort(_ date: Date?) -> String? {
        guard let date else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "E HH:mm"
        return fmt.string(from: date)
    }

    /// Absolute clock time of the last successful fetch, e.g. "오후 2:32 갱신".
    /// Empty for the sentinel `.distantPast` (sample data).
    static func updatedClock(_ date: Date) -> String {
        guard date != .distantPast else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "a h:mm"
        return "\(fmt.string(from: date)) 갱신"
    }
}
