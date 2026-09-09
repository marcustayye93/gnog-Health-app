import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Medication.sortOrder) private var medications: [Medication]

    @StateObject private var health = HealthKitManager.shared
    @State private var reminders = ReminderSettings.load()
    @State private var notificationsOn = false
    @State private var showAddMed = false
    @State private var exportDoc: NogDocument?
    @State private var showImporter = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Reminders
                Section("Reminders") {
                    Toggle("Medication reminders", isOn: $notificationsOn)
                        .onChange(of: notificationsOn) { _, on in
                            Task {
                                if on {
                                    let granted = await NotificationManager.shared.requestAuthorization()
                                    if !granted {
                                        await MainActor.run { notificationsOn = false }
                                        return
                                    }
                                }
                                refreshNotifications()
                            }
                        }
                    if notificationsOn {
                        Toggle("Morning (\(reminders.morningHour):\(String(format: "%02d", reminders.morningMinute)))",
                               isOn: $reminders.morningEnabled)
                        Toggle("Afternoon (\(reminders.afternoonHour):\(String(format: "%02d", reminders.afternoonMinute)))",
                               isOn: $reminders.afternoonEnabled)
                        Stepper("Morning time: \(timeString(reminders.morningHour, reminders.morningMinute))",
                                value: Binding(
                                    get: { reminders.morningHour * 60 + reminders.morningMinute },
                                    set: {
                                        reminders.morningHour = $0 / 60
                                        reminders.morningMinute = $0 % 60
                                    }),
                                in: 0...1439, step: 15)
                        Stepper("Afternoon time: \(timeString(reminders.afternoonHour, reminders.afternoonMinute))",
                                value: Binding(
                                    get: { reminders.afternoonHour * 60 + reminders.afternoonMinute },
                                    set: {
                                        reminders.afternoonHour = $0 / 60
                                        reminders.afternoonMinute = $0 % 60
                                    }),
                                in: 0...1439, step: 15)
                    }
                    Text("Reminders are scheduled on this phone — no server, no account, works offline.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .onChange(of: reminders) { _, _ in
                    reminders.save()
                    refreshNotifications()
                }

                // MARK: - Medications
                Section("Medications") {
                    ForEach(medications) { med in
                        NavigationLink {
                            MedicationEditor(medication: med)
                        } label: {
                            HStack {
                                Text(med.name)
                                Spacer()
                                Text("\(med.group) · \(med.time)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if med.packOnly {
                                    Text("pill-day only")
                                        .font(.caption2).foregroundStyle(.teal)
                                }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for i in indexSet { context.delete(medications[i]) }
                        try? context.save()
                        refreshNotifications()
                    }
                    Button { showAddMed = true } label: {
                        Label("Add medication", systemImage: "plus")
                    }
                }

                // MARK: - HealthKit
                Section("Apple Health") {
                    if !health.isAvailable {
                        Text("HealthKit isn't available on this device.")
                            .foregroundStyle(.secondary)
                    } else if health.isAuthorized {
                        Label("Connected — flow and symptoms sync to Apple Health",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.teal)
                    } else {
                        Button("Connect Apple Health") {
                            Task { await health.requestAuthorization() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if let err = health.lastError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    Text("Reads sleep, HRV and resting heart rate from your Apple Watch for Insights. You choose exactly what to share.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                // MARK: - Data
                Section("Your data") {
                    Button("Export JSON") { exportJSON() }
                    Button("Export CSV") { exportCSV() }
                    Button("Import JSON backup") { showImporter = true }
                    if let importError {
                        Text(importError).font(.caption).foregroundStyle(.red)
                    }
                    Text("Gnog keeps everything on this phone. Export any time so your history is never trapped.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Text("No account. No analytics. No ads. Your cycle and medication data lives in this app's private store on your device (and your iCloud backup, if enabled). Reminders are local notifications — nothing is sent anywhere.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAddMed) { AddMedicationSheet() }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                importBackup(result)
            }
            .fileExporter(
                isPresented: Binding(
                    get: { exportDoc != nil },
                    set: { if !$0 { exportDoc = nil } }
                ),
                document: exportDoc ?? NogDocument(filename: "gnog.json", data: Data(), contentType: .json),
                contentType: exportDoc?.contentType ?? .json,
                defaultFilename: exportDoc?.filename ?? "gnog.json"
            ) { _ in exportDoc = nil }
            .task {
                let center = UNUserNotificationCenter.current()
                let settings = await center.notificationSettings()
                notificationsOn = settings.authorizationStatus == .authorized
                    && (reminders.morningEnabled || reminders.afternoonEnabled)
            }
        }
    }

    private func timeString(_ h: Int, _ m: Int) -> String {
        String(format: "%d:%02d", h, m)
    }

    private func refreshNotifications() {
        let meds: [Medication] = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        let starts: [Date] = ((try? context.fetch(FetchDescriptor<PeriodStart>())) ?? []).map(\.date)
        if notificationsOn {
            NotificationManager.shared.rescheduleAll(
                medications: meds, anchor: PackStore.anchor,
                periodStarts: starts, settings: reminders)
        } else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
        SnapshotWriter.update(context: context)
    }

    // MARK: - Export / import

    private func backupDictionary() -> [String: Any] {
        let logs: [DayLog] = (try? context.fetch(FetchDescriptor<DayLog>())) ?? []
        let doses: [DoseLog] = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        let starts: [Date] = ((try? context.fetch(FetchDescriptor<PeriodStart>())) ?? []).map(\.date)
        let iso = ISO8601DateFormatter()
        return [
            "app": "gnog-schedules", "version": 1,
            "exportedAt": iso.string(from: Date()),
            "packAnchor": iso.string(from: PackStore.anchor),
            "periodStarts": starts.map { iso.string(from: $0) },
            "medications": medications.map { [
                "id": $0.id.uuidString, "name": $0.name, "group": $0.group,
                "time": $0.time, "packOnly": $0.packOnly, "sortOrder": $0.sortOrder,
            ] },
            "dayLogs": logs.map { [
                "date": iso.string(from: $0.date), "flow": $0.flow as Any? ?? NSNull(),
                "moods": $0.moods, "note": $0.note,
            ] },
            "doseLogs": doses.map { [
                "date": iso.string(from: $0.date),
                "medicationID": $0.medicationID.uuidString, "taken": $0.taken,
            ] },
        ]
    }

    private func exportJSON() {
        guard let data = try? JSONSerialization.data(withJSONObject: backupDictionary(),
                                                    options: [.prettyPrinted, .sortedKeys]) else { return }
        exportDoc = NogDocument(filename: "gnog-schedules-backup.json",
                                data: data, contentType: .json)
    }

    private func exportCSV() {
        let logs: [DayLog] = (try? context.fetch(FetchDescriptor<DayLog>())) ?? []
        let doses: [DoseLog] = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        let starts: [Date] = ((try? context.fetch(FetchDescriptor<PeriodStart>())) ?? []).map(\.date)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        var rows = ["date,flow,moods,note,pack_phase,pack_day,meds_taken"]
        let dates = Set(logs.map { $0.date.startOfNogDay }
            + doses.map { $0.date.startOfNogDay }
            + starts.map { $0.startOfNogDay }).sorted()
        let nameByID = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0.name) })
        for d in dates {
            let log = logs.first { $0.date.startOfNogDay == d }
            let phase = PackLogic.phase(on: d, anchor: PackStore.anchor)
            let takenNames = doses.filter { $0.date.startOfNogDay == d && $0.taken }
                .compactMap { nameByID[$0.medicationID] }
            let phaseStr: String
            let dayStr: String
            switch phase {
            case .active(let n): phaseStr = "active"; dayStr = "\(n)"
            case .placebo(let n): phaseStr = "placebo"; dayStr = "\(n)"
            }
            let note = (log?.note ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            rows.append([
                iso.string(from: d), log?.flow ?? "",
                (log?.moods ?? []).joined(separator: "|"),
                "\"\(note)\"", phaseStr, dayStr,
                takenNames.joined(separator: "|"),
            ].joined(separator: ","))
        }
        exportDoc = NogDocument(filename: "gnog-schedules.csv",
                                data: Data(rows.joined(separator: "\n").utf8),
                                contentType: .commaSeparatedText)
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard json?["app"] as? String == "gnog-schedules",
                  let meds = json?["medications"] as? [[String: Any]] else {
                importError = "That file doesn't look like a Gnog backup."
                return
            }
            let iso = ISO8601DateFormatter()
            // Replace medications wholesale; merge logs.
            for m in medications { context.delete(m) }
            for (i, m) in meds.enumerated() {
                context.insert(Medication(
                    id: UUID(uuidString: m["id"] as? String ?? "") ?? UUID(),
                    name: m["name"] as? String ?? "Medication",
                    group: m["group"] as? String ?? "Morning",
                    time: m["time"] as? String ?? "08:00",
                    packOnly: m["packOnly"] as? Bool ?? false,
                    sortOrder: m["sortOrder"] as? Int ?? i))
            }
            if let anchorStr = json?["packAnchor"] as? String,
               let anchor = iso.date(from: anchorStr) {
                PackStore.anchor = anchor.startOfNogDay
            }
            for s in (json?["periodStarts"] as? [String] ?? []).compactMap({ iso.date(from: $0) }) {
                let day = s.startOfNogDay
                let exists = (try? context.fetch(FetchDescriptor<PeriodStart>()))?.contains { $0.date.startOfNogDay == day } ?? false
                if !exists { context.insert(PeriodStart(date: day)) }
            }
            for l in (json?["dayLogs"] as? [[String: Any]] ?? []) {
                guard let ds = l["date"] as? String, let date = iso.date(from: ds) else { continue }
                let day = date.startOfNogDay
                if let existing = (try? context.fetch(FetchDescriptor<DayLog>()))?.first(where: { $0.date.startOfNogDay == day }) {
                    existing.flow = l["flow"] as? String
                    existing.moods = l["moods"] as? [String] ?? []
                    existing.note = l["note"] as? String ?? ""
                } else {
                    context.insert(DayLog(date: day, flow: l["flow"] as? String,
                                          moods: l["moods"] as? [String] ?? [],
                                          note: l["note"] as? String ?? ""))
                }
            }
            try context.save()
            importError = nil
            NogRefresh.afterDataChange(context: context)
        } catch {
            importError = "Couldn't read that file: \(error.localizedDescription)"
        }
    }
}

// MARK: - File export document

struct NogDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    let filename: String
    let data: Data
    let contentType: UTType

    init(filename: String, data: Data, contentType: UTType) {
        self.filename = filename
        self.data = data
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        filename = "import.json"
        data = Data()
        contentType = .json
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Medication editor

private struct MedicationEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var medication: Medication

    var body: some View {
        Form {
            TextField("Name", text: $medication.name)
            Picker("Group", selection: $medication.group) {
                Text("Morning").tag("Morning")
                Text("Afternoon").tag("Afternoon")
            }
            Text("The group decides which reminder slot this medication appears in.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Time (HH:MM)", text: $medication.time)
                .textInputAutocapitalization(.never)
            Toggle("Only on active pill days", isOn: $medication.packOnly)
            Text("Use for Liza-style meds skipped during placebo week.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .navigationTitle("Edit medication")
        .onDisappear {
            try? context.save()
            NogRefresh.afterDataChange(context: context)
        }
    }
}

private struct AddMedicationSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Medication.sortOrder) private var medications: [Medication]

    @State private var name = ""
    @State private var group = "Morning"
    @State private var hour = 8
    @State private var minute = 0
    @State private var packOnly = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Medication name", text: $name)
                Picker("Group", selection: $group) {
                    Text("Morning").tag("Morning")
                    Text("Afternoon").tag("Afternoon")
                }
                DatePicker("Time", selection: Binding(
                    get: {
                        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
                    },
                    set: {
                        let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                        hour = c.hour ?? 8
                        minute = c.minute ?? 0
                    }), displayedComponents: .hourAndMinute)
                Toggle("Only on active pill days", isOn: $packOnly)
            }
            .navigationTitle("Add medication")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let nextOrder = (medications.map(\.sortOrder).max() ?? -1) + 1
                        context.insert(Medication(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Medication" : name.trimmingCharacters(in: .whitespacesAndNewlines),
                            group: group,
                            time: String(format: "%02d:%02d", hour, minute),
                            packOnly: packOnly,
                            sortOrder: nextOrder))
                        try? context.save()
                        NogRefresh.afterDataChange(context: context)
                        dismiss()
                    }
                }
            }
        }
    }
}
