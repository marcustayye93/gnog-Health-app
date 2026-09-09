import SwiftUI
import SwiftData

struct PackView: View {
    @Environment(\.modelContext) private var context
    @State private var anchor: Date = PackStore.anchor
    @State private var showSaved = false

    private var today: Date { Date().startOfNogDay }
    private var dates: [Date] { PackLogic.packDates(anchor: anchor.startOfNogDay) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("This pack started \(anchor.startOfNogDay.prettyShort).")
                            .font(.headline)
                        Text("Today: \(PackLogic.phase(on: today, anchor: anchor.startOfNogDay).headline).")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                        ForEach(dates, id: \.self) { date in
                            let phase = PackLogic.phase(on: date, anchor: anchor.startOfNogDay)
                            let isToday = date == today
                            let isPast = date < today
                            ZStack {
                                Circle()
                                    .fill(phase.isActive ? Color.teal.opacity(0.18) : Color.orange.opacity(0.2))
                                    .opacity(isPast ? 0.45 : 1)
                                Text(dayNumber(phase))
                                    .font(.subheadline).bold()
                                    .foregroundStyle(phase.isActive ? .teal : .orange)
                                    .opacity(isPast ? 0.5 : 1)
                            }
                            .frame(height: 46)
                            .overlay {
                                if isToday {
                                    Circle().stroke(Color.accentColor, lineWidth: 3)
                                }
                            }
                            .accessibilityLabel("\(date.prettyShort): \(phase.headline)")
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)

                    HStack(spacing: 18) {
                        legendDot(.teal, "Active pill")
                        legendDot(.orange, "Placebo")
                    }
                    .font(.caption).foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Adjust schedule").font(.headline)
                        Text("If a pack starts late or you skip days, update when this pack's day 1 was. Everything recalculates.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        DatePicker("Pack started (day 1 of active pills)",
                                   selection: $anchor, displayedComponents: .date)
                        HStack {
                            Button("− 1 day") { anchor = anchor.nogAdding(days: -1) }
                            Spacer()
                            Button("Start new pack today") { anchor = today }
                            Spacer()
                            Button("+ 1 day") { anchor = anchor.nogAdding(days: 1) }
                        }
                        .buttonStyle(.bordered)
                        Button("Save pack schedule") { save() }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        if showSaved {
                            Text("Saved ✓ — reminders rescheduled").font(.footnote).foregroundStyle(.teal)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                }
                .padding()
            }
            .navigationTitle("Pill Pack")
        }
    }

    private func dayNumber(_ phase: PackLogic.Phase) -> String {
        switch phase {
        case .active(let d): return "\(d)"
        case .placebo(let d): return "\(d)"
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label)
        }
    }

    private func save() {
        PackStore.anchor = anchor.startOfNogDay
        NogRefresh.afterDataChange(context: context)
        showSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { showSaved = false }
    }
}
