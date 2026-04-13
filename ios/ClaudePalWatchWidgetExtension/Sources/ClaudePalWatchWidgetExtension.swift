import SwiftUI
import WidgetKit

private struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

private struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .after(Date().addingTimeInterval(300))))
    }
}

private struct PlaceholderWidgetView: View {
    let entry: PlaceholderEntry

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "cloud.fill")
                .font(.headline)
            Text("ClaudePal")
                .font(.caption2)
        }
    }
}

struct ClaudePalWatchStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudePalWatchStatus", provider: PlaceholderProvider()) { entry in
            PlaceholderWidgetView(entry: entry)
        }
        .configurationDisplayName("ClaudePal")
        .description("Claude Code session status.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct ClaudePalWatchWidgetExtension: WidgetBundle {
    var body: some Widget {
        ClaudePalWatchStatusWidget()
    }
}
