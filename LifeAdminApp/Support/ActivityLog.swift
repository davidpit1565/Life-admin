import Foundation

struct ActivityLogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let message: String
}

/// A visible, on-device record of everything the app decided to do on its own — merging a
/// duplicate, auto-filling a contact, escalating to AI, acting on a notification button — so
/// autonomy stays accountable instead of invisible. Nothing here is ever sent anywhere.
@MainActor
final class ActivityLog: ObservableObject {
    static let shared = ActivityLog()

    @Published private(set) var entries: [ActivityLogEntry] = []

    private let maxEntries = 50
    private let storageKey = "activityLogEntries"

    private init() {
        load()
    }

    func record(_ message: String, date: Date = Date()) {
        entries.insert(ActivityLogEntry(id: UUID(), date: date, message: message), at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        entries = (try? JSONDecoder().decode([ActivityLogEntry].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
