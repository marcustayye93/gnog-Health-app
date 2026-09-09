import WidgetKit
import SwiftUI

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(),
                                 snapshot: WidgetSnapshot.read() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(),
                                  snapshot: WidgetSnapshot.read() ?? .placeholder)
        // The app rewrites the snapshot on every data change and every launch,
        // so the timeline just needs a daily refresh as a backstop.
        let nextMidnight = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 5),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(24 * 3600)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
}

// MARK: - Small widget: period countdown + pill-pack ring

struct NogSmallView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.periodHeadline)
                .font(.headline)
                .minimumScaleFactor(0.8)
            Text(snapshot.periodSubline)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: max(0.02, snapshot.pillProgress))
                        .stroke(Color.pink,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 34, height: 34)
                Text(snapshot.pillHeadline)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "gnog://today"))
    }
}

struct NogSmallWidget: Widget {
    let kind = "NogSmallWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            NogSmallView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Gnog Countdown")
        .description("Days until your period and pill-pack progress.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Medium widget: today's meds + next period

struct NogMediumView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today's meds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(snapshot.medsTaken)/\(snapshot.medsTotal) taken")
                    .font(.title2).bold()
                    .minimumScaleFactor(0.8)
                ProgressView(value: Double(snapshot.medsTaken),
                             total: Double(max(snapshot.medsTotal, 1)))
                .tint(.pink)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(snapshot.periodHeadline)
                    .font(.headline)
                    .multilineTextAlignment(.trailing)
                    .minimumScaleFactor(0.8)
                Text(snapshot.pillHeadline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "gnog://today"))
    }
}

struct NogMediumWidget: Widget {
    let kind = "NogMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            NogMediumView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Gnog Today")
        .description("Today's medication progress and cycle status.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Bundle

@main
struct GnogWidgets: WidgetBundle {
    var body: some Widget {
        NogSmallWidget()
        NogMediumWidget()
    }
}
