import SwiftUI
import LifeAdminCore
@main struct LifeAdminApp: App { @StateObject private var store = ItemStore(); var body: some Scene { WindowGroup { RootTabView().environmentObject(store) } } }
final class ItemStore: ObservableObject { @Published var items: [LifeAdminItem] = []; let parser = NaturalLanguageParser(); func add(text: String) { let e=parser.parse(text); var item=LifeAdminItem(title: e.title ?? String(localized:"item.untitled"), category: e.category ?? .other, dueDate: e.date, amount: e.amount, currency: e.currency, recurrence: e.recurring ?? .none, reminderOffsets: e.reminderOffsets ?? [30]); item.priority = PriorityEngine().priority(for: item); items.append(item) } }
