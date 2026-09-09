import Foundation

/// Cycle predictions from logged period starts. Pure functions — no I/O.
enum PredictionEngine {
    enum CyclePhase: String {
        case menstrual, follicular, ovulation, luteal, unknown

        var displayName: String { rawValue.capitalized }
    }

    /// Average cycle length from the gaps between the last 3 period starts.
    /// Falls back to 28 when there are fewer than 2 starts.
    static func averageCycleLength(from starts: [Date], fallback: Int = 28) -> Int {
        let sorted = starts.map { $0.startOfNogDay }.sorted()
        guard sorted.count >= 2 else { return fallback }
        var gaps: [Int] = []
        for i in 1..<sorted.count { gaps.append(sorted[i - 1].nogDays(to: sorted[i])) }
        let recent = Array(gaps.suffix(3)).filter { $0 > 0 }
        guard !recent.isEmpty else { return fallback }
        return Int(round(Double(recent.reduce(0, +)) / Double(recent.count)))
    }

    static func lastStart(from starts: [Date]) -> Date? {
        starts.map { $0.startOfNogDay }.max()
    }

    static func predictedNextPeriod(from starts: [Date], cycleLength: Int? = nil) -> Date? {
        guard let last = lastStart(from: starts) else { return nil }
        let len = cycleLength ?? averageCycleLength(from: starts)
        return last.nogAdding(days: len)
    }

    /// Which day of the current bleed is `date`? (1-based, nil if not in a bleed.)
    /// A bleed is the 8 days following a logged start.
    static func periodDayNumber(on date: Date, starts: [Date]) -> Int? {
        let day = date.startOfNogDay
        for s in starts.map({ $0.startOfNogDay }).sorted().reversed() {
            let d = s.nogDays(to: day)
            if d >= 0 && d < 8 { return d + 1 }
            if d < 0 { continue }
            break
        }
        return nil
    }

    /// Cycle phase for `date`, counting from the most recent start.
    static func phase(on date: Date, starts: [Date], cycleLength: Int? = nil) -> CyclePhase {
        guard let last = lastStart(from: starts) else { return .unknown }
        let len = cycleLength ?? averageCycleLength(from: starts)
        let d = ((last.nogDays(to: date.startOfNogDay) % len) + len) % len
        switch d {
        case 0..<7: return .menstrual
        case 7..<13: return .follicular
        case 13..<16: return .ovulation
        default: return .luteal
        }
    }

    /// Estimated fertile window: ovulation ~= predicted period minus 14 days,
    /// fertile = ovulation-5 ... ovulation+1.
    static func fertileWindow(predictedPeriod: Date) -> (start: Date, end: Date) {
        let ovulation = predictedPeriod.nogAdding(days: -14)
        return (ovulation.nogAdding(days: -5), ovulation.nogAdding(days: 1))
    }

    /// Average bleed length: counts consecutive days with a flow log after each start.
    static func averagePeriodLength(starts: [Date], dayLogs: [DayLog]) -> Double? {
        let byDay = Dictionary(uniqueKeysWithValues: dayLogs.map { ($0.date.startOfNogDay, $0) })
        var lengths: [Int] = []
        for s in starts.map({ $0.startOfNogDay }) {
            var n = 0
            for d in 0..<8 {
                let day = s.nogAdding(days: d)
                if let log = byDay[day], log.flow != nil, log.flow != "spotting" { n += 1 }
                else if d == 0 { n += 1 }  // the start day itself counts
                else { break }
            }
            if n > 0 { lengths.append(n) }
        }
        guard !lengths.isEmpty else { return nil }
        return Double(lengths.reduce(0, +)) / Double(lengths.count)
    }
}
