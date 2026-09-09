import Foundation
import SwiftData

/// Rebuilds the widget snapshot from the SwiftData store.
/// Called on launch and after every data change. App target only —
/// the widget extension only ever *reads* the snapshot file.
enum SnapshotWriter {
    /// Must be called from the main thread — every caller is UI code.
    static func update(context: ModelContext) {
        let today = Date().startOfNogDay
        let anchor = PackStore.anchor
        let phase = PackLogic.phase(on: today, anchor: anchor)

        let starts: [Date] = ((try? context.fetch(FetchDescriptor<PeriodStart>())) ?? []).map(\.date)
        let meds: [Medication] = (try? context.fetch(
            FetchDescriptor<Medication>(sortBy: [SortDescriptor(\Medication.sortOrder)])
        )) ?? []
        let doses: [DoseLog] = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []

        let periodHeadline: String
        let periodSubline: String
        var nextPeriod: Date?
        if let n = PredictionEngine.periodDayNumber(on: today, starts: starts) {
            periodHeadline = "Day \(n) of period"
            periodSubline = "Log your flow below"
            nextPeriod = PredictionEngine.predictedNextPeriod(from: starts)
        } else if let predicted = PredictionEngine.predictedNextPeriod(from: starts) {
            nextPeriod = predicted
            let d = today.nogDays(to: predicted)
            if d <= 0 {
                periodHeadline = "Period due today"
            } else if d == 1 {
                periodHeadline = "Period tomorrow"
            } else {
                periodHeadline = "Period in \(d) days"
            }
            periodSubline = "Predicted \(predicted.prettyShort)"
        } else {
            periodHeadline = "Gnog Schedules"
            periodSubline = "Log your first period"
        }

        let due = meds.filter { !($0.packOnly && !phase.isActive) }
        let takenIDs = Set(doses.filter { $0.date == today && $0.taken }.map(\.medicationID))
        let takenCount = due.filter { takenIDs.contains($0.id) }.count

        WidgetSnapshot(
            periodHeadline: periodHeadline,
            periodSubline: periodSubline,
            pillHeadline: phase.headline,
            pillProgress: phase.packProgress,
            medsTaken: takenCount,
            medsTotal: due.count,
            nextPeriodDate: nextPeriod,
            updatedAt: Date()
        ).write()
    }
}

/// One call to run after any data change: rebuilds notifications + widget snapshot.
enum NogRefresh {
    /// Must be called from the main thread — every caller is UI code.
    static func afterDataChange(context: ModelContext) {
        let meds: [Medication] = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        let starts: [Date] = ((try? context.fetch(FetchDescriptor<PeriodStart>())) ?? []).map(\.date)
        NotificationManager.shared.rescheduleAll(
            medications: meds,
            anchor: PackStore.anchor,
            periodStarts: starts,
            settings: ReminderSettings.load()
        )
        SnapshotWriter.update(context: context)
    }
}
