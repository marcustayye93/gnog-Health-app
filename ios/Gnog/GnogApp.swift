import SwiftUI
import SwiftData

@main
struct GnogApp: App {
    let container: ModelContainer

    @State private var selectedTab = 0

    init() {
        // Shared App Group store so the widget extension reads the same data.
        // Falls back to the default store if the App Group isn't available
        // (e.g. entitlements not yet configured) — the app always launches.
        let schema = Schema([DayLog.self, Medication.self, DoseLog.self, PeriodStart.self])
        let container: ModelContainer
        if let groupURL = GnogShared.groupURL {
            let url = groupURL.appending(path: "gnog.store")
            let config = ModelConfiguration(schema: schema, url: url)
            if let c = try? ModelContainer(for: schema, configurations: [config]) {
                container = c
            } else {
                container = try! ModelContainer(for: schema)
            }
        } else {
            container = try! ModelContainer(for: schema)
        }
        self.container = container
        seedIfNeeded(context: ModelContext(container))
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                TodayView()
                    .tabItem { Label("Today", systemImage: "sun.max") }
                    .tag(0)
                CalendarView()
                    .tabItem { Label("Calendar", systemImage: "calendar") }
                    .tag(1)
                PackView()
                    .tabItem { Label("Pack", systemImage: "pills") }
                    .tag(2)
                InsightsView()
                    .tabItem { Label("Insights", systemImage: "chart.bar") }
                    .tag(3)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gear") }
                    .tag(4)
            }
            .onOpenURL { url in
                // Widget deep links: gnog://today, gnog://calendar, gnog://pack
                guard url.scheme == "gnog" else { return }
                switch url.host {
                case "calendar": selectedTab = 1
                case "pack": selectedTab = 2
                default: selectedTab = 0
                }
            }
            .task {
                // Rebuild reminders + widget snapshot on every launch.
                await MainActor.run {
                    NogRefresh.afterDataChange(context: ModelContext(container))
                }
            }
        }
        .modelContainer(container)
    }

    // MARK: - First-launch seed

    private func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: "gnog.seeded.v1") else { return }
        let existing = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        if existing.isEmpty {
            let seed: [(String, String, String, Bool, Int)] = [
                ("Prebiotic", "Morning", "08:00", false, 0),
                ("Probiotic", "Morning", "08:00", false, 1),
                ("Iron supplement", "Morning", "08:00", false, 2),
                ("Liza", "Afternoon", "13:30", true, 3),
                ("Lexapro", "Afternoon", "13:30", false, 4),
                ("Abilify", "Afternoon", "13:30", false, 5),
            ]
            for (name, group, time, packOnly, order) in seed {
                context.insert(Medication(name: name, group: group,
                                          time: time, packOnly: packOnly, sortOrder: order))
            }
        }
        let starts = (try? context.fetch(FetchDescriptor<PeriodStart>())) ?? []
        if starts.isEmpty {
            context.insert(PeriodStart(date: Date.nogDate(2026, 9, 7)))
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: "gnog.seeded.v1")
    }
}
