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
                        // An item overdue by a day and one due next month otherwise look
                        // identical here save for an 8pt dot — the one signal that actually
                        // needs to grab attention shouldn't be that easy to miss.
                        .foregroundStyle(isOverdue ? .red : .secondary)
                }
            }

            Spacer()

            Circle()
                .fill(item.priority.indicatorColor)
                .frame(width: 8, height: 8)
                .accessibilityLabel(item.priority.displayName)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var isOverdue: Bool {
        guard let dueDate = item.dueDate, item.status == .active else { return false }
        return dueDate < Date()
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
        // A renewal quietly costing more than last time was previously only visible by opening
        // the item's own edit screen — surfacing it right in the list is what actually makes it
        // catchable at a glance, the same way ItemDetailView's own priceChangeDescription does.
        if let priceChangeBadge {
            parts.append(priceChangeBadge)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var priceChangeBadge: String? {
        guard let percent = RecurrenceEngine().priceChangePercent(for: item) else { return nil }
        let rounded = Int(percent.rounded())
        guard rounded != 0 else { return nil }
        return rounded > 0
            ? String(format: String(localized: "itemDetail.priceChangeUpCompact"), rounded)
            : String(format: String(localized: "itemDetail.priceChangeDownCompact"), abs(rounded))
    }
}
