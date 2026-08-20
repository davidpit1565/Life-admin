import Foundation
import SwiftData
import LifeAdminCore

@Model
final class PersistedItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var itemDescription: String?
    var category: LifeCategory
    var status: ItemStatus
    var priority: Priority
    var priorityOverride: Priority?
    var dueDate: Date?
    var endDate: Date?
    var amount: Decimal?
    var currency: String?
    var recurrence: Recurrence
    var recurrenceRule: String?
    var reminderOffsets: [Int]
    var notes: String?
    var tags: [String]
    var attachments: [Attachment]
    var contact: ContactInfo?
    var location: String?
    var createdAt: Date
    var updatedAt: Date
    // EventKit identifiers, kept only here (not on LifeAdminItem) since they're a pure
    // app-target persistence concern — lets CalendarSyncService update/remove the same
    // calendar event or reminder instead of creating a duplicate every time.
    var calendarEventIdentifier: String?
    var reminderIdentifier: String?

    init(item: LifeAdminItem) {
        id = item.id
        title = item.title
        itemDescription = item.description
        category = item.category
        status = item.status
        priority = item.priority
        priorityOverride = item.priorityOverride
        dueDate = item.dueDate
        endDate = item.endDate
        amount = item.amount
        currency = item.currency
        recurrence = item.recurrence
        recurrenceRule = item.recurrenceRule
        reminderOffsets = item.reminderOffsets
        notes = item.notes
        tags = item.tags
        attachments = item.attachments
        contact = item.contact
        location = item.location
        createdAt = item.createdAt
        updatedAt = item.updatedAt
    }

    func apply(_ item: LifeAdminItem) {
        title = item.title
        itemDescription = item.description
        category = item.category
        status = item.status
        priority = item.priority
        priorityOverride = item.priorityOverride
        dueDate = item.dueDate
        endDate = item.endDate
        amount = item.amount
        currency = item.currency
        recurrence = item.recurrence
        recurrenceRule = item.recurrenceRule
        reminderOffsets = item.reminderOffsets
        notes = item.notes
        tags = item.tags
        attachments = item.attachments
        contact = item.contact
        location = item.location
        updatedAt = item.updatedAt
    }

    var asItem: LifeAdminItem {
        LifeAdminItem(
            id: id,
            title: title,
            description: itemDescription,
            category: category,
            status: status,
            priority: priority,
            priorityOverride: priorityOverride,
            dueDate: dueDate,
            endDate: endDate,
            amount: amount,
            currency: currency,
            recurrence: recurrence,
            recurrenceRule: recurrenceRule,
            reminderOffsets: reminderOffsets,
            notes: notes,
            tags: tags,
            attachments: attachments,
            contact: contact,
            location: location,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
