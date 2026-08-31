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
                    // Without this, VoiceOver reads the message and the relative timestamp as two
                    // separate swipe stops on the same row — ItemRow's own two-line layout already
                    // combines the same way for the same reason.
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle(String(localized: "activityLog.title"))
    }
}
