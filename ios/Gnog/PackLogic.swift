import Foundation

/// The 28-day pill pack. `anchor` is a day-1-of-active-pills date.
/// Day index 0..<21  -> active pill (day n of 21)
/// Day index 21..<28 -> placebo   (day n of 7)
/// Pure functions on Date — no I/O, fully testable.
enum PackLogic {
    enum Phase: Equatable {
        case active(day: Int)    // day 1...21
        case placebo(day: Int)   // day 1...7

        var isActive: Bool {
            if case .active = self { return true }
            return false
        }

        var headline: String {
            switch self {
            case .active(let d): return "Pill day \(d) of 21"
            case .placebo(let d): return "Placebo day \(d) of 7"
            }
        }

        /// 0.0 ... 1.0 progress across the whole 28-day pack.
        var packProgress: Double {
            switch self {
            case .active(let d): return Double(d - 1) / 28.0
            case .placebo(let d): return Double(21 + d - 1) / 28.0
            }
        }
    }

    /// 0..<28 index of `date` within its pack, relative to `anchor`.
    static func dayIndex(on date: Date, anchor: Date) -> Int {
        let days = anchor.startOfNogDay.nogDays(to: date)
        return ((days % 28) + 28) % 28
    }

    static func phase(on date: Date, anchor: Date) -> Phase {
        let idx = dayIndex(on: date, anchor: anchor)
        if idx < 21 { return .active(day: idx + 1) }
        return .placebo(day: idx - 20)
    }

    /// The 28 dates of the pack that starts at `anchor`.
    static func packDates(anchor: Date) -> [Date] {
        (0..<28).map { anchor.startOfNogDay.nogAdding(days: $0) }
    }

    /// Next date (including `date` itself) on which the placebo week begins.
    static func nextPlaceboStart(onOrAfter date: Date, anchor: Date) -> Date {
        var d = date.startOfNogDay
        for _ in 0..<28 {
            if case .placebo(day: 1) = phase(on: d, anchor: anchor) { return d }
            d = d.nogAdding(days: 1)
        }
        return d
    }

    /// Next date (including `date` itself) on which a new pack begins.
    static func nextPackStart(onOrAfter date: Date, anchor: Date) -> Date {
        var d = date.startOfNogDay
        for _ in 0..<28 {
            if case .active(day: 1) = phase(on: d, anchor: anchor) { return d }
            d = d.nogAdding(days: 1)
        }
        return d
    }
}
