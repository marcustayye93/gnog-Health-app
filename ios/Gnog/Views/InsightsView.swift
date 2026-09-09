import SwiftUI
import SwiftData

struct InsightsView: View {
    @Query(sort: \PeriodStart.date) private var periodStarts: [PeriodStart]
    @Query(sort: \DayLog.date) private var dayLogs: [DayLog]
    @Query(sort: \Medication.sortOrder) private var medications: [Medication]
    @Query private var doseLogs: [DoseLog]

    @StateObject private var health = HealthKitManager.shared
    @State private var recovery: [DailyRecovery] = []

    private var starts: [Date] { periodStarts.map(\.date).map(\.startOfNogDay).sorted() }
    private var avgCycle: Int { PredictionEngine.averageCycleLength(from: starts) }

    // Consecutive days (ending today/yesterday) with every due med taken.
    private var streak: Int {
        let today = Date().startOfNogDay
        let anchor = PackStore.anchor
        var n = 0
        var d = today
        // Allow today to be incomplete: start counting from yesterday if today's
        // meds aren't all taken yet.
        if !allTaken(on: today, anchor: anchor) { d = today.nogAdding(days: -1) }
        while allTaken(on: d, anchor: anchor) {
            n += 1
            d = d.nogAdding(days: -1)
            if n > 365 { break }
        }
        return n
    }

    private func allTaken(on day: Date, anchor: Date) -> Bool {
        let phase = PackLogic.phase(on: day, anchor: anchor)
        let due = medications.filter { !($0.packOnly && !phase.isActive) }
        guard !due.isEmpty else { return false }
        let taken = Set(doseLogs.filter { $0.date.startOfNogDay == day && $0.taken }.map(\.medicationID))
        return due.allSatisfy { taken.contains($0.id) }
    }

    private var moodByPhase: [(phase: String, moods: [(String, Int)])] {
        var counts: [String: [String: Int]] = [:]
        for log in dayLogs {
            let ph = PredictionEngine.phase(on: log.date, starts: starts, cycleLength: avgCycle).rawValue
            for m in log.moods { counts[ph, default: [:]][m, default: 0] += 1 }
        }
        return ["menstrual", "follicular", "ovulation", "luteal"].compactMap { ph in
            guard let c = counts[ph], !c.isEmpty else { return nil }
            let top = c.sorted { $0.value > $1.value }.prefix(4).map { ($0.key, $0.value) }
            return (ph, top)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Streak hero
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(streak)")
                                .font(.system(size: 44, weight: .bold))
                            Text(streak == 1 ? "day streak" : "day streak")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("🔥").font(.system(size: 40))
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(colors: [.pink.opacity(0.25), .orange.opacity(0.18)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Cycle history
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Cycle history").font(.headline).padding(.bottom, 6)
                        if starts.isEmpty {
                            Text("No periods logged yet.").foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(starts.enumerated().reversed()), id: \.offset) { i, s in
                                let gap = i > 0 ? "\(starts[i - 1].nogDays(to: s)) days" : "—"
                                HStack {
                                    Text("Started \(s.prettyShort)")
                                    Spacer()
                                    Text(gap).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                                Divider()
                            }
                            HStack {
                                Text("Average cycle").bold()
                                Spacer()
                                Text("\(avgCycle) days").bold()
                            }
                            .padding(.vertical, 8)
                            if let avgLen = PredictionEngine.averagePeriodLength(starts: starts, dayLogs: dayLogs) {
                                HStack {
                                    Text("Average period length")
                                    Spacer()
                                    Text(String(format: "%.1f days", avgLen)).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)

                    // Moods by phase
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Moods by cycle phase").font(.headline)
                        if moodByPhase.isEmpty {
                            Text("Log some moods and patterns will show up here.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(moodByPhase, id: \.phase) { entry in
                                Text(entry.phase.capitalized)
                                    .font(.subheadline).bold()
                                    .padding(.top, 4)
                                let max = entry.moods.first?.1 ?? 1
                                ForEach(entry.moods, id: \.0) { mood, count in
                                    HStack {
                                        Text(LogOptions.moodLabel(mood))
                                            .font(.subheadline)
                                            .frame(width: 110, alignment: .leading)
                                        GeometryReader { geo in
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.accentColor.opacity(0.7))
                                                .frame(width: geo.size.width * CGFloat(count) / CGFloat(max),
                                                       height: 12)
                                        }
                                        .frame(height: 12)
                                        Text("\(count)")
                                            .font(.caption).foregroundStyle(.secondary)
                                            .frame(width: 28, alignment: .trailing)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)

                    // Sleep & HRV from Apple Watch (when connected)
                    if health.isAuthorized {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sleep & recovery (Apple Watch)").font(.headline)
                            if recovery.isEmpty {
                                Text("No recent data.").foregroundStyle(.secondary)
                            } else {
                                ForEach(recovery.suffix(7).reversed()) { r in
                                    HStack {
                                        Text(r.date.formatted(.dateTime.weekday(.abbreviated)))
                                            .frame(width: 44, alignment: .leading)
                                        Spacer()
                                        if let s = r.sleepHours {
                                            Text("😴 \(String(format: "%.1f", s))h")
                                        }
                                        if let h = r.hrvMs {
                                            Text("HRV \(Int(h))ms")
                                        }
                                    }
                                    .font(.subheadline)
                                    .padding(.vertical, 4)
                                    Divider()
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                    }
                }
                .padding()
            }
            .navigationTitle("Insights")
            .task {
                if health.isAuthorized {
                    recovery = await health.fetchRecoveryData()
                }
            }
        }
    }
}
