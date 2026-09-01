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
    var recurrenceAnchorDay: Int?
    var previousAmount: Decimal?
    var reminderOffsets: [Int]
    var notes: String?
    var tags: [String]
    var attachments: [Attachment]
    var contact: ContactInfo?
    var location: String?
    // A concrete default (rather than leaving this like every other non-optional array property
    // above, none of which need one — they all predate any real user data) is what lets SwiftData
    // open an existing store from before this property existed via lightweight migration, instead
    // of failing to load on launch for anyone who already has items saved.
    var documentFields: [DocumentField] = []
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
        recurrenceAnchorDay = item.recurrenceAnchorDay
        previousAmount = item.previousAmount
        reminderOffsets = item.reminderOffsets
        notes = item.notes
        tags = item.tags
        attachments = item.attachments
        contact = item.contact
        location = item.location
        documentFields = item.documentFields
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
        recurrenceAnchorDay = item.recurrenceAnchorDay
        previousAmount = item.previousAmount
        reminderOffsets = item.reminderOffsets
        notes = item.notes
        tags = item.tags
        attachments = item.attachments
        contact = item.contact
        location = item.location
        documentFields = item.documentFields
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
            recurrenceAnchorDay: recurrenceAnchorDay,
            previousAmount: previousAmount,
            reminderOffsets: reminderOffsets,
            notes: notes,
            tags: tags,
            attachments: attachments,
            contact: contact,
            location: location,
            documentFields: documentFields,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
