import Foundation
import SwiftData

// MARK: - Day log (period / mood / flow tracking)

@Model
final class DayLog {
    @Attribute(.unique) var date: Date   // start of day, local time
    var flow: String?                    // "spotting" | "light" | "medium" | "heavy"
    var moods: [String]
    var note: String

    init(date: Date, flow: String? = nil, moods: [String] = [], note: String = "") {
        self.date = date
        self.flow = flow
        self.moods = moods
        self.note = note
    }
}

// MARK: - Medication

@Model
final class Medication {
    var id: UUID
    var name: String
    var group: String        // "Morning" | "Afternoon" (user-editable)
    var time: String         // "08:00" — display + notification scheduling
    var packOnly: Bool       // true = only on active pill days (e.g. Liza)
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, group: String, time: String, packOnly: Bool = false, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.group = group
        self.time = time
        self.packOnly = packOnly
        self.sortOrder = sortOrder
    }
}

// MARK: - Dose log (taken / not taken per day)

@Model
final class DoseLog {
    var date: Date            // start of day, local time
    var medicationID: UUID
    var taken: Bool

    init(date: Date, medicationID: UUID, taken: Bool = true) {
        self.date = date
        self.medicationID = medicationID
        self.taken = taken
    }
}

// MARK: - Period start dates (drives predictions)

@Model
final class PeriodStart {
    @Attribute(.unique) var date: Date   // start of day, local time

    init(date: Date) {
        self.date = date
    }
}

// MARK: - App settings (standard UserDefaults; app-only concerns)

struct ReminderSettings: Codable, Equatable {
    var morningEnabled: Bool = true
    var afternoonEnabled: Bool = true
    var morningHour: Int = 8
    var morningMinute: Int = 0
    var afternoonHour: Int = 13
    var afternoonMinute: Int = 30

    static let key = "gnog.reminderSettings.v1"

    static func load() -> ReminderSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(ReminderSettings.self, from: data) else {
            return ReminderSettings()
        }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Pack anchor (shared App Group so the widget could read it too)

enum PackStore {
    private static let key = "gnog.packAnchor.v1"

    static var anchor: Date {
        get {
            let ts = GnogShared.groupDefaults?.double(forKey: key) ?? 0
            if ts > 0 { return Date(timeIntervalSince1970: ts) }
            return Date.nogDate(2026, 9, 12)
        }
        set {
            GnogShared.groupDefaults?.set(newValue.timeIntervalSince1970, forKey: key)
        }
    }
}

// MARK: - Date helpers

extension Date {
    /// Local-midnight date from components. Avoids all timezone string-parsing traps.
    static func nogDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    var startOfNogDay: Date { Calendar.current.startOfDay(for: self) }

    func nogAdding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self.startOfNogDay)!
    }

    /// Whole days from `self` (start of day) to `other` (start of day). Negative if past.
    func nogDays(to other: Date) -> Int {
        Calendar.current.dateComponents([.day], from: self.startOfNogDay, to: other.startOfNogDay).day ?? 0
    }

    var prettyShort: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: self)
    }

    var prettyWeekday: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMM"
        return f.string(from: self)
    }
}
