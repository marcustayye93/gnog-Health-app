import Foundation

/// Shared constants and the lightweight widget snapshot.
/// This file is compiled into BOTH the app target and the widget extension target.
/// The widget never touches SwiftData directly — the app writes a JSON snapshot
/// to the shared App Group container, and the widget reads it.
enum GnogShared {
    /// Change this to your own group, e.g. group.com.yourname.gnog
    static let appGroupID = "group.com.gnog.schedules"

    static var groupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var groupDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
}

/// Everything the widgets need, written by the app whenever data changes.
struct WidgetSnapshot: Codable {
    var periodHeadline: String   // e.g. "Day 3 of period" or "Period in 4 days"
    var periodSubline: String    // e.g. "Predicted Mon, Sep 14"
    var pillHeadline: String     // e.g. "Pill day 14 of 21" or "Placebo day 3 of 7"
    var pillProgress: Double     // 0.0 ... 1.0 across the 28-day pack
    var medsTaken: Int           // today's taken count
    var medsTotal: Int           // today's total due
    var nextPeriodDate: Date?
    var updatedAt: Date

    static let fileName = "gnog-widget.json"

    static func read() -> WidgetSnapshot? {
        guard let url = GnogShared.groupURL?.appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func write() {
        guard let url = GnogShared.groupURL?.appendingPathComponent(fileName) else { return }
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(
            periodHeadline: "Period in 4 days",
            periodSubline: "Predicted",
            pillHeadline: "Pill day 14 of 21",
            pillProgress: 0.5,
            medsTaken: 2,
            medsTotal: 6,
            nextPeriodDate: nil,
            updatedAt: Date()
        )
    }
}
