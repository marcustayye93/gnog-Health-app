import SwiftUI
import SwiftData

struct CalendarView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DayLog.date) private var dayLogs: [DayLog]
    @Query(sort: \PeriodStart.date) private var periodStarts: [PeriodStart]

    @State private var cursor: Date = Date()
    @State private var selectedDay: Date?

    private var starts: [Date] { periodStarts.map(\.date) }
    private var predicted: Date? { PredictionEngine.predictedNextPeriod(from: starts) }

    private var monthCells: [Date?] {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: cursor))!
        let firstWeekday = cal.component(.weekday, from: monthStart) // 1 = Sunday
        let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)!.count
        var cells: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        for d in 1...daysInMonth {
            cells.append(cal.date(byAdding: .day, value: d - 1, to: monthStart))
        }
        return cells
    }

    private func log(for date: Date) -> DayLog? {
        dayLogs.first { $0.date.startOfNogDay == date.startOfNogDay }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                HStack {
                    Button { cursor = Calendar.current.date(byAdding: .month, value: -1, to: cursor)! } label: {
                        Image(systemName: "chevron.left").font(.title2)
                    }
                    Spacer()
                    Text(cursor.formatted(.dateTime.month(.wide).year()))
                        .font(.title2).bold()
                    Spacer()
                    Button { cursor = Calendar.current.date(byAdding: .month, value: 1, to: cursor)! } label: {
                        Image(systemName: "chevron.right").font(.title2)
                    }
                }
                .padding(.horizontal)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { d in
                        Text(d).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(monthCells.indices, id: \.self) { i in
                        if let date = monthCells[i] {
                            dayCell(date)
                        } else {
                            Color.clear.frame(height: 44)
                        }
                    }
                }
                .padding(.horizontal)

                HStack(spacing: 18) {
                    legendDot(.pink, "Period")
                    legendDot(.pink.opacity(0.35), "Predicted")
                    legendDot(.teal, "Logged")
                }
                .font(.caption).foregroundStyle(.secondary)

                Spacer()
            }
            .navigationTitle("Calendar")
            .sheet(item: $selectedDay) { day in
                DayDetailSheet(date: day)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ date: Date) -> some View {
        let day = date.startOfNogDay
        let isPeriod = PredictionEngine.periodDayNumber(on: day, starts: starts) != nil
        let isPredicted = predicted.map { $0.startOfNogDay == day } ?? false
        let hasLog = (log(for: day)?.moods.isEmpty == false) || log(for: day)?.flow != nil
        let isToday = day == Date().startOfNogDay

        Button { selectedDay = day } label: {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.body)
                    .foregroundStyle(.primary)
                HStack(spacing: 3) {
                    if isPeriod { Circle().fill(.pink).frame(width: 7, height: 7) }
                    else if isPredicted { Circle().stroke(.pink.opacity(0.7), lineWidth: 1.5).frame(width: 7, height: 7) }
                    if hasLog { Circle().fill(.teal).frame(width: 7, height: 7) }
                }
                .frame(height: 8)
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(isToday ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label)
        }
    }
}

// MARK: - Day detail sheet

private struct DayDetailSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DayLog.date) private var dayLogs: [DayLog]
    @Query(sort: \PeriodStart.date) private var periodStarts: [PeriodStart]

    let date: Date
    @State private var selectedFlow: String?
    @State private var selectedMoods: Set<String> = []
    @State private var note: String = ""

    private var day: Date { date.startOfNogDay }
    private var existing: DayLog? { dayLogs.first { $0.date.startOfNogDay == day } }
    private var isPeriodStart: Bool { periodStarts.contains { $0.date.startOfNogDay == day } }
    private var phase: PackLogic.Phase { PackLogic.phase(on: day, anchor: PackStore.anchor) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cycle") {
                    LabeledContent("Pack", value: phase.headline)
                    if PredictionEngine.periodDayNumber(on: day, starts: periodStarts.map(\.date)) != nil {
                        if isPeriodStart {
                            Button("Remove period start", role: .destructive) {
                                if let s = periodStarts.first(where: { $0.date.startOfNogDay == day }) {
                                    context.delete(s)
                                    try? context.save()
                                    NogRefresh.afterDataChange(context: context)
                                }
                            }
                        } else {
                            Text("Period day (part of a logged bleed)")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button(isPeriodStart ? "Remove period start" : "Mark as period start") {
                            if let s = periodStarts.first(where: { $0.date.startOfNogDay == day }) {
                                context.delete(s)
                            } else {
                                context.insert(PeriodStart(date: day))
                            }
                            try? context.save()
                            NogRefresh.afterDataChange(context: context)
                        }
                    }
                }
                Section("Flow") {
                    FlowLayout(spacing: 8) {
                        ForEach(LogOptions.flows, id: \.self) { f in
                            Chip(title: LogOptions.flowLabel(f), selected: selectedFlow == f) {
                                selectedFlow = (selectedFlow == f) ? nil : f
                            }
                        }
                    }
                }
                Section("Mood") {
                    FlowLayout(spacing: 8) {
                        ForEach(LogOptions.moods, id: \.self) { m in
                            Chip(title: LogOptions.moodLabel(m), selected: selectedMoods.contains(m)) {
                                if selectedMoods.contains(m) { selectedMoods.remove(m) }
                                else { selectedMoods.insert(m) }
                            }
                        }
                    }
                }
                Section("Note") {
                    TextField("Note", text: $note, axis: .vertical)
                }
                Section {
                    Button("Save") { save() }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(date.prettyShort)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                selectedFlow = existing?.flow
                selectedMoods = Set(existing?.moods ?? [])
                note = existing?.note ?? ""
            }
        }
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let log = existing {
            log.flow = selectedFlow
            log.moods = Array(selectedMoods)
            log.note = trimmed
        } else {
            context.insert(DayLog(date: day, flow: selectedFlow,
                                  moods: Array(selectedMoods), note: trimmed))
        }
        try? context.save()
        HealthKitManager.shared.saveDayLog(date: day, flow: selectedFlow, moods: Array(selectedMoods))
        NogRefresh.afterDataChange(context: context)
        dismiss()
    }
}

// @Query-friendly Identifiable wrapper for sheet presentation.
extension Date: @retroactive Identifiable {
    public var id: Date { self }
}
