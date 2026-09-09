import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DayLog.date) private var dayLogs: [DayLog]
    @Query(sort: \Medication.sortOrder) private var medications: [Medication]
    @Query private var doseLogs: [DoseLog]
    @Query(sort: \PeriodStart.date) private var periodStarts: [PeriodStart]

    @State private var selectedFlow: String?
    @State private var selectedMoods: Set<String> = []
    @State private var note: String = ""
    @State private var savedFlash = false

    private var today: Date { Date().startOfNogDay }
    private var starts: [Date] { periodStarts.map(\.date) }
    private var phase: PackLogic.Phase { PackLogic.phase(on: today, anchor: PackStore.anchor) }

    private var todayLog: DayLog? {
        dayLogs.first { $0.date.startOfNogDay == today }
    }

    private func isTaken(_ med: Medication) -> Bool {
        doseLogs.first { $0.date == today && $0.medicationID == med.id }?.taken ?? false
    }

    private func toggleTaken(_ med: Medication) {
        if let log = doseLogs.first(where: { $0.date == today && $0.medicationID == med.id }) {
            log.taken.toggle()
        } else {
            context.insert(DoseLog(date: today, medicationID: med.id, taken: true))
        }
        try? context.save()
        SnapshotWriter.update(context: context)
    }

    // MARK: - Cards

    @ViewBuilder
    private var periodCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let n = PredictionEngine.periodDayNumber(on: today, starts: starts) {
                Text("🩸 Day \(n) of your period")
                    .font(.title3).bold()
                Text("Log your flow below — it sharpens future predictions.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if let next = PredictionEngine.predictedNextPeriod(from: starts) {
                let d = today.nogDays(to: next)
                Text("📅 Next period expected \(d <= 0 ? "today" : d == 1 ? "tomorrow" : "in \(d) days")")
                    .font(.title3).bold()
                Text("Predicted \(next.prettyShort), based on your logged history.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("📅 Welcome to Gnog")
                    .font(.title3).bold()
                Text("Log your next period start and predictions will appear here.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var packBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch phase {
            case .active(let d):
                Text("💊 Pill day \(d) of 21").font(.title3).bold()
                let toPlacebo = 21 - d
                Text(toPlacebo == 1 ? "Placebo week starts tomorrow." : "Placebo week starts in \(toPlacebo) days.")
                    .font(.subheadline).foregroundStyle(.secondary)
            case .placebo(let d):
                Text("💊 Placebo day \(d) of 7 — no Liza").font(.title3).bold()
                let toNew = 7 - d
                Text(toNew == 1 ? "New pack starts tomorrow." : "New pack starts in \(toNew) days.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(phase.isActive ? Color.teal.opacity(0.12) : Color.orange.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func medGroupCard(name: String, time: String, meds: [Medication]) -> some View {
        let done = meds.filter(isTaken).count
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name).font(.headline)
                Spacer()
                Text("\(time) · \(done)/\(meds.count)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(meds) { med in
                Button { toggleTaken(med) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isTaken(med) ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(isTaken(med) ? .teal : .secondary)
                        Text(med.name)
                            .strikethrough(isTaken(med))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            let skipped = medications.filter { $0.group == name && $0.packOnly && !phase.isActive }
            if !skipped.isEmpty {
                Text("⏸ \(skipped.map(\.name).joined(separator: ", ")) skipped — placebo week")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    // MARK: - Save

    private func prefillFromToday() {
        guard let log = todayLog else { return }
        selectedFlow = log.flow
        selectedMoods = Set(log.moods)
        note = log.note
    }

    private func saveDay() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let log = todayLog {
            log.flow = selectedFlow
            log.moods = Array(selectedMoods)
            log.note = trimmed
        } else {
            context.insert(DayLog(date: today, flow: selectedFlow,
                                  moods: Array(selectedMoods), note: trimmed))
        }
        // Auto-detect a new period start: real flow logged, and no start in the last 10 days.
        if let flow = selectedFlow, flow != "spotting" {
            let recent = starts.contains { $0.nogDays(to: today) >= 0 && $0.nogDays(to: today) <= 10 }
            if !recent {
                context.insert(PeriodStart(date: today))
            }
        }
        try? context.save()
        HealthKitManager.shared.saveDayLog(date: today, flow: selectedFlow, moods: Array(selectedMoods))
        NogRefresh.afterDataChange(context: context)
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { savedFlash = false }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    periodCard
                    packBanner

                    let groups = Dictionary(grouping: medications, by: \.group)
                        .sorted { $0.key < $1.key }
                    ForEach(groups, id: \.key) { name, meds in
                        let visible = meds
                            .filter { !($0.packOnly && !phase.isActive) }
                            .sorted { $0.sortOrder < $1.sortOrder }
                        if !visible.isEmpty {
                            medGroupCard(name: name,
                                         time: meds.first?.time ?? "",
                                         meds: visible)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Log today").font(.headline)
                        Text("Flow").font(.caption).foregroundStyle(.secondary)
                        FlowLayout(spacing: 8) {
                            ForEach(LogOptions.flows, id: \.self) { f in
                                Chip(title: LogOptions.flowLabel(f),
                                     selected: selectedFlow == f) {
                                    selectedFlow = (selectedFlow == f) ? nil : f
                                }
                            }
                        }
                        Text("Mood").font(.caption).foregroundStyle(.secondary)
                        FlowLayout(spacing: 8) {
                            ForEach(LogOptions.moods, id: \.self) { m in
                                Chip(title: LogOptions.moodLabel(m),
                                     selected: selectedMoods.contains(m)) {
                                    if selectedMoods.contains(m) { selectedMoods.remove(m) }
                                    else { selectedMoods.insert(m) }
                                }
                            }
                        }
                        Text("Note").font(.caption).foregroundStyle(.secondary)
                        TextField("Anything worth remembering…", text: $note, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3)
                        Button("Save today's log") { saveDay() }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        if savedFlash {
                            Text("Saved ✓").font(.footnote).foregroundStyle(.teal)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                }
                .padding()
            }
            .navigationTitle(Date().prettyWeekday)
            .onAppear(perform: prefillFromToday)
        }
    }
}

// Simple flow layout for chips (iOS 17 has no built-in flow layout in SwiftUI).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    private func layout(proposal: ProposedViewSize, subviews: Subviews)
        -> (rows: [[(index: Int, frame: CGRect)]], size: CGSize)
    {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[(index: Int, frame: CGRect)]] = []
        var current: [(index: Int, frame: CGRect)] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                rows.append(current)
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
                current = []
            }
            current.append((i, CGRect(x: x, y: y, width: size.width, height: size.height)))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        if !current.isEmpty { rows.append(current) }
        let totalHeight = rows.isEmpty ? 0 : y + rowHeight
        return (rows, CGSize(width: proposal.width ?? 0, height: totalHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in layout(proposal: proposal, subviews: subviews).rows {
            for (i, frame) in row {
                subviews[i].place(
                    at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                    proposal: .unspecified
                )
            }
        }
    }
}
