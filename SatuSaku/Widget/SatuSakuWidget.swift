import SwiftUI
import WidgetKit

struct SatuSakuWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    static var sample: SatuSakuWidgetEntry {
        SatuSakuWidgetEntry(
            date: .now,
            snapshot: WidgetSnapshot(
                streakDays: 7,
                totalXP: 4_500,
                currentLevel: 4,
                goalID: UUID(uuidString: "A1B2C3D4-E5F6-4789-ABCD-0123456789AB"),
                goalTitle: "Japan Trip",
                goalProgress: 0.65,
                nextDepositDate: Calendar.current.date(byAdding: .day, value: 3, to: .now)
            )
        )
    }

    var logDepositURL: URL? {
        guard let goalID = snapshot.goalID else { return nil }
        var components = URLComponents()
        components.scheme = "satusaku"
        components.host = "log-deposit"
        components.queryItems = [URLQueryItem(name: "goal", value: goalID.uuidString)]
        return components.url
    }
}

struct SatuSakuWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SatuSakuWidgetEntry {
        .sample
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (SatuSakuWidgetEntry) -> Void
    ) {
        completion(context.isPreview ? .sample : currentEntry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<SatuSakuWidgetEntry>) -> Void
    ) {
        let entry = currentEntry()
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: .now)
            ?? .now.addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func currentEntry() -> SatuSakuWidgetEntry {
        SatuSakuWidgetEntry(date: .now, snapshot: WidgetSharedData.load())
    }
}

struct SatuSakuWidget: Widget {
    let kind = "SatuSakuWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SatuSakuWidgetProvider()) { entry in
            SatuSakuWidgetView(entry: entry)
                .widgetURL(entry.logDepositURL)
        }
        .configurationDisplayName("Satu Saku")
        .description("Track your saving streak and goal progress.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct SatuSakuWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SatuSakuWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumWidget
            default:
                smallWidget
            }
        }
        .containerBackground(Color(red: 0.96, green: 0.98, blue: 0.95), for: .widget)
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image("PipoAuthHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                Text("Satu Saku")
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            Text("🔥 \(entry.snapshot.streakDays) Day Streak")
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Level \(entry.snapshot.currentLevel) · \(entry.snapshot.totalXP.formatted()) XP")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(4)
    }

    private var mediumWidget: some View {
        HStack(spacing: 12) {
            Image("PipoAuthHero")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 82)

            VStack(alignment: .leading, spacing: 6) {
                if let title = entry.snapshot.goalTitle {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)

                    HStack {
                        Text("Progress")
                        Spacer(minLength: 4)
                        Text(entry.snapshot.goalProgress, format: .percent.precision(.fractionLength(0)))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ProgressView(value: entry.snapshot.goalProgress)
                        .tint(Color(red: 0.20, green: 0.55, blue: 0.38))

                    HStack {
                        Text(nextDepositText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        if let url = entry.logDepositURL {
                            Link(destination: url) {
                                Label("Log deposit", systemImage: "plus.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                    }
                } else {
                    Text("No active personal goal")
                        .font(.headline)
                    Text("Create a goal in Satu Saku to track progress here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(4)
    }

    private var nextDepositText: String {
        guard let date = entry.snapshot.nextDepositDate else {
            return "Flexible schedule"
        }
        return "Next: \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

#Preview(as: .systemSmall) {
    SatuSakuWidget()
} timeline: {
    SatuSakuWidgetEntry.sample
}

#Preview(as: .systemMedium) {
    SatuSakuWidget()
} timeline: {
    SatuSakuWidgetEntry.sample
}
