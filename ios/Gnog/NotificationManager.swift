import Foundation
import UserNotifications

/// Local notifications. Because the pill phase changes daily, we schedule
/// 28 individual non-repeating reminders (one per day) with phase-correct
/// content, and rebuild them whenever meds, the pack anchor, or period
/// data changes. No server involved — everything fires on-device.
final class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    /// Rebuilds all reminders. Call on launch and after any data change.
    func rescheduleAll(medications: [Medication],
                       anchor: Date,
                       periodStarts: [Date],
                       settings: ReminderSettings) {
        center.removeAllPendingNotificationRequests()
        guard settings.morningEnabled || settings.afternoonEnabled else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let morningMeds = medications
            .filter { $0.group == "Morning" }
            .sorted { $0.sortOrder < $1.sortOrder }
        let afternoonMeds = medications
            .filter { $0.group == "Afternoon" }
            .sorted { $0.sortOrder < $1.sortOrder }

        for offset in 0..<28 {
            guard let date = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let phase = PackLogic.phase(on: date, anchor: anchor)

            if settings.morningEnabled, !morningMeds.isEmpty {
                let names = morningMeds.map(\.name).joined(separator: ", ")
                add(id: "gnog.morning.\(offset)",
                    title: "🌅 Time for your morning meds",
                    body: "\(names) — tap to check them off in Gnog.",
                    at: date, hour: settings.morningHour, minute: settings.morningMinute)
            }

            if settings.afternoonEnabled, !afternoonMeds.isEmpty {
                let due = afternoonMeds.filter { !($0.packOnly && !phase.isActive) }
                guard !due.isEmpty else { continue }
                let skipped = afternoonMeds.filter { $0.packOnly && !phase.isActive }.map(\.name)
                let names = due.map(\.name).joined(separator: ", ")
                let title: String
                let body: String
                switch phase {
                case .active(let d):
                    title = "💊 Pill day \(d) of 21 — meds time"
                    body = "\(names) — tap to check them off in Gnog."
                case .placebo(let d):
                    title = "💊 Placebo day \(d) of 7 — meds time"
                    let skipNote = skipped.isEmpty ? "" : "No \(skipped.joined(separator: ", ")) today. "
                    body = "\(skipNote)\(names) — tap to check them off in Gnog."
                }
                add(id: "gnog.afternoon.\(offset)", title: title, body: body,
                    at: date, hour: settings.afternoonHour, minute: settings.afternoonMinute)
            }
        }

        // Period-due reminders (2 days before + morning of).
        if let next = PredictionEngine.predictedNextPeriod(from: periodStarts) {
            let twoDays = next.nogAdding(days: -2)
            if twoDays.startOfNogDay >= today {
                add(id: "gnog.period.2d",
                    title: "📅 Period expected in 2 days",
                    body: "Your period is predicted for \(next.prettyShort).",
                    at: twoDays, hour: 9, minute: 0)
            }
            if next.startOfNogDay >= today {
                add(id: "gnog.period.today",
                    title: "🩸 Period expected today",
                    body: "Log it in Gnog when it starts to keep predictions sharp.",
                    at: next, hour: 9, minute: 0)
            }
        }

        // Placebo-week-start reminder.
        let placeboStart = PackLogic.nextPlaceboStart(onOrAfter: today, anchor: anchor)
        if placeboStart > today {
            let skipped = afternoonMeds.filter(\.packOnly).map(\.name)
            let note = skipped.isEmpty ? "" : " No \(skipped.joined(separator: ", ")) for 7 days."
            add(id: "gnog.placebo.start",
                title: "💊 Placebo week starts today",
                body: "Your other meds stay the same.\(note)",
                at: placeboStart, hour: 9, minute: 0)
        }
    }

    // MARK: - Private

    private func add(id: String, title: String, body: String, at date: Date, hour: Int, minute: Int) {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = minute
        guard let fireDate = Calendar.current.date(from: comps), fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }
}
