# Gnog Schedules — native iOS app

The Apple-ecosystem companion to the Gnog Schedules PWA: a private period &
medication tracker built with **SwiftUI + SwiftData**, targeting **iOS 17+**.
No third-party dependencies. Everything from the PWA is here, plus what only
a native app can do: **home-screen widgets**, **HealthKit sync** (writes flow +
symptoms, reads sleep/HRV from Apple Watch), and **local notifications**
scheduled entirely on-device.

## Project layout

```
ios/
├── Gnog.xcodeproj/                 # Open this in Xcode
├── Gnog/                           # App target "Gnog"
│   ├── GnogApp.swift               # @main — ModelContainer (App Group store),
│   │                              #   first-launch seed, 5-tab TabView, deep links
│   ├── Models.swift               # DayLog, Medication, DoseLog, PeriodStart,
│   │                              #   ReminderSettings, PackStore, Date helpers
│   ├── PackLogic.swift            # 28-day pack math (pure functions)
│   ├── PredictionEngine.swift     # Cycle predictions (pure functions)
│   ├── HealthKitManager.swift     # HealthKit auth/read/write
│   ├── NotificationManager.swift  # 28-day phase-aware local notifications
│   ├── SnapshotWriter.swift       # Widget snapshot + refresh-on-data-change
│   ├── FlowMood.swift            # Flow/mood constants + Chip/FlowLayout UI
│   ├── Views/                     # Today, Calendar, Pack, Insights, Settings
│   ├── Info.plist                 # HealthKit usage descriptions, gnog:// scheme
│   └── Gnog.entitlements           # HealthKit + App Groups
└── GnogWidgets/                    # Widget extension target "GnogWidgets"
    ├── GnogWidgets.swift           # Small (countdown + pack ring) + Medium
    │                              #   (meds progress) widgets, TimelineProvider
    ├── Info.plist                 # WidgetKit extension point
    └── GnogWidgets.entitlements    # App Groups (shared with the app)
```

`Gnog/Shared/AppGroup.swift` is compiled into **both** targets. The app writes
a small JSON snapshot (`gnog-widget.json`) to the shared App Group container
whenever data changes; the widgets only read that file — they never touch
SwiftData. The SwiftData store itself also lives in the App Group
(`gnog.store`), so app and widget share one source of truth.

## What you need

- A Mac with **Xcode 15+**
- An **Apple Developer Program** membership (for TestFlight / device installs)
- ~15 minutes

## Steps

### 1. Get the code onto the Mac
Copy the whole `ios/` folder to the Mac (AirDrop, USB, or push it to a GitHub
repo and clone it there).

### 2. Open the project
Double-click `ios/Gnog.xcodeproj`. You should see two targets: **Gnog** (the app)
and **GnogWidgets** (the widget extension).

### 3. Signing & bundle IDs
1. Select the **Gnog** target → **Signing & Capabilities**.
2. Set **Team** to your Apple Developer team (automatic signing is already on).
3. Change the **Bundle Identifier** from `com.gnog.schedules` to something unique
   to you, e.g. `com.yourname.nogschedules`.
4. Select the **GnogWidgets** target and change its bundle ID to match plus the
   extension suffix, e.g. `com.yourname.nogschedules.GnogWidgets`.
5. If you renamed the bundle ID, also rename the App Group: in both targets'
   **Signing & Capabilities**, change the App Group to
   `group.com.yourname.nogschedules`, and update `GnogShared.appGroupID` in
   `Gnog/Shared/AppGroup.swift` to the same string. (Skip this if you keep the
   default IDs.)

### 4. Capabilities (already wired — just verify)
Both are declared in the `.entitlements` files and referenced by the project:
- **App Groups** (`group.com.gnog.schedules`) — on both targets. With automatic
  signing, Xcode registers the group with Apple on first build.
- **HealthKit** — on the **Gnog** target only.

If Xcode shows a warning on either capability, click **Fix Issue** / let it
repair provisioning — that's normal on first setup.

The `Info.plist` already contains the required usage descriptions:
`NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription`.

### 5. Build & run
Select an iPhone (or your own device) as the run destination and press **⌘R**.
First launch seeds Chesa's data: morning/afternoon medications, pack anchor
2026-09-12, and the 2026-09-07 period start.

### 6. TestFlight
1. Bump the version in the **Gnog** target → **General** (Version / Build).
2. **Product → Archive**, then **Distribute App → App Store Connect**.
3. In App Store Connect, add the build to TestFlight and invite Chesa as an
   internal/external tester. She installs via the TestFlight app — no App Store
   review needed for internal testers.

## How it maps to the PWA

| PWA | Native app |
|---|---|
| Today tab, med checklist, flow/mood chips | `TodayView` — identical, plus haptic-feel native toggles |
| Calendar tab, day detail, mark period start | `CalendarView` — month grid + detail sheet |
| Pack tab, 28-day grid, anchor editor | `PackView` — same, native DatePicker/steppers |
| Insights, cycle history, mood bars, streak | `InsightsView` — same + Apple Watch sleep/HRV section |
| Settings, med editor, export/import | `SettingsView` — same, native share sheet / file importer |
| Server-sent web push | `NotificationManager` — 28 days of phase-aware **local** notifications, rebuilt on every data change; period-due + placebo-week alerts included |
| — | `HealthKitManager` — writes flow/symptoms to Apple Health, reads watch data |
| — | `GnogWidgets` — small countdown + medium med-progress widgets, tap to deep-link (`gnog://today`) |

Medication schedule, pack math (`PackLogic`), and predictions
(`PredictionEngine`) are the same rules as the PWA: 21 active + 7 placebo,
Liza hidden during placebo week, one daily reminder per group.

## Notes for future you

- **Notifications are local.** There is no push server in the native app —
  `rescheduleAll()` is called on launch and after every data change, covering
  the next 28 days. If Chesa edits meds or the pack anchor, reminders rebuild.
- **HealthKit is optional.** Denying access changes nothing about the app's
  own tracking; the Insights watch section simply stays hidden.
- **Never trapped again:** Settings → Export JSON/CSV works from day one, and
  the JSON backup restores fully via Import.
