import SwiftUI
import LifeAdminCore

extension LifeCategory {
    var symbolName: String {
        switch self {
        case .documents: return "doc.text.fill"
        case .insurance: return "shield.lefthalf.filled"
        case .money: return "banknote.fill"
        case .bills: return "doc.plaintext.fill"
        case .subscriptions: return "arrow.triangle.2.circlepath.circle.fill"
        case .car: return "car.fill"
        case .home: return "house.fill"
        case .health: return "heart.fill"
        case .travel: return "airplane"
        case .work: return "briefcase.fill"
        case .education: return "graduationcap.fill"
        case .shopping: return "bag.fill"
        case .warranties: return "checkmark.seal.fill"
        case .memberships: return "medal.fill"
        case .appointments: return "calendar"
        case .personal: return "person.fill"
        case .family: return "person.3.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .documents, .bills: return .indigo
        case .insurance, .warranties: return .teal
        case .money, .subscriptions: return .green
        case .car, .travel: return .blue
        case .home: return .brown
        case .health: return .pink
        case .work, .education: return .purple
        case .shopping: return .orange
        case .memberships, .appointments: return .cyan
        case .personal, .family: return .mint
        case .other: return .gray
        }
    }

    /// `rawValue.capitalized` (e.g. "Everytwomonths") is not a translation — it silently stays
    /// in English even when the rest of the app is showing Hebrew, Arabic, or any other language
    /// the user picked in Settings.
    var displayName: String {
        switch self {
        case .documents: return String(localized: "category.documents")
        case .insurance: return String(localized: "category.insurance")
        case .money: return String(localized: "category.money")
        case .bills: return String(localized: "category.bills")
        case .subscriptions: return String(localized: "category.subscriptions")
        case .car: return String(localized: "category.car")
        case .home: return String(localized: "category.home")
        case .health: return String(localized: "category.health")
        case .travel: return String(localized: "category.travel")
        case .work: return String(localized: "category.work")
        case .education: return String(localized: "category.education")
        case .shopping: return String(localized: "category.shopping")
        case .warranties: return String(localized: "category.warranties")
        case .memberships: return String(localized: "category.memberships")
        case .appointments: return String(localized: "category.appointments")
        case .personal: return String(localized: "category.personal")
        case .family: return String(localized: "category.family")
        case .other: return String(localized: "category.other")
        }
    }
}

extension Priority {
    var indicatorColor: Color {
        switch self {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .secondary
        }
    }

    var displayName: String {
        switch self {
        case .low: return String(localized: "priority.low")
        case .medium: return String(localized: "priority.medium")
        case .high: return String(localized: "priority.high")
        case .critical: return String(localized: "priority.critical")
        }
    }
}

extension ItemStatus {
    var displayName: String {
        switch self {
        case .active: return String(localized: "status.active")
        case .completed: return String(localized: "status.completed")
        case .snoozed: return String(localized: "status.snoozed")
        case .archived: return String(localized: "status.archived")
        }
    }
}

extension Recurrence {
    var displayName: String {
        switch self {
        case .none: return String(localized: "recurrence.none")
        case .daily: return String(localized: "recurrence.daily")
        case .weekly: return String(localized: "recurrence.weekly")
        case .biweekly: return String(localized: "recurrence.biweekly")
        case .monthly: return String(localized: "recurrence.monthly")
        case .everyTwoMonths: return String(localized: "recurrence.everyTwoMonths")
        case .quarterly: return String(localized: "recurrence.quarterly")
        case .everySixMonths: return String(localized: "recurrence.everySixMonths")
        case .yearly: return String(localized: "recurrence.yearly")
        case .custom: return String(localized: "recurrence.custom")
        }
    }
}
