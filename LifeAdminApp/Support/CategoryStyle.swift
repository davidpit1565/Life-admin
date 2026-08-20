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
}
