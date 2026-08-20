import SwiftUI
import LifeAdminCore

struct ItemRow: View {
    let item: LifeAdminItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(item.category.tintColor.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: item.category.symbolName)
                    .foregroundStyle(item.category.tintColor)
                    .font(.system(size: 16, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Circle()
                .fill(item.priority.indicatorColor)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var subtitleText: String? {
        var parts: [String] = []
        if let dueDate = item.dueDate {
            parts.append(dueDate.formatted(.relative(presentation: .named)))
        }
        if let amount = item.amount {
            if let currency = item.currency {
                parts.append(amount.formatted(.currency(code: currency)))
            } else {
                parts.append(amount.formatted())
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
