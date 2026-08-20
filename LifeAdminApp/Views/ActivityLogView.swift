import SwiftUI

struct ActivityLogView: View {
    @ObservedObject private var log = ActivityLog.shared

    var body: some View {
        List {
            if log.entries.isEmpty {
                ContentUnavailableView(
                    String(localized: "activityLog.empty"),
                    systemImage: "clock.arrow.circlepath"
                )
            } else {
                ForEach(log.entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message)
                        Text(entry.date.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "activityLog.title"))
    }
}
