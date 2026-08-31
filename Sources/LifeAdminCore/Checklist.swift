import Foundation

/// A single "life admin" item worth having a reminder for, shown to a user who hasn't added one
/// yet — the starter checklist requested after seeing real users get burned by the things that
/// fall between the cracks (a lapsed passport, an insurance policy nobody renewed). `titleKey` is
/// a Localizable.strings key, not display text: this package has no bundle of its own, so the
/// View layer resolves it the same way it resolves every other user-facing string in the app.
public struct ChecklistSuggestion: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var titleKey: String
    public var category: LifeCategory
    public var suggestedRecurrence: Recurrence
    /// SF Symbol name for the checklist row's icon.
    public var systemImage: String
    /// Lowercased keywords checked against an existing item's title, within the same category, to
    /// decide the user already has this covered. Category alone can't tell "car insurance" apart
    /// from "home insurance" — both are `.insurance` — so most entries need at least one keyword;
    /// a suggestion whose category is otherwise unambiguous can leave this empty.
    public var matchKeywords: [String]

    public init(id: String, titleKey: String, category: LifeCategory, suggestedRecurrence: Recurrence, systemImage: String, matchKeywords: [String] = []) {
        self.id = id
        self.titleKey = titleKey
        self.category = category
        self.suggestedRecurrence = suggestedRecurrence
        self.systemImage = systemImage
        self.matchKeywords = matchKeywords
    }

    /// A deliberately curated starting set, not an exhaustive dump of every possible reminder
    /// type — easy to extend later, but a shorter, genuinely high-value list beats an overwhelming
    /// one nobody works through. Keywords mirror the same vocabulary NaturalLanguageParser already
    /// recognizes (English/Hebrew/Spanish/French) so an item added by typing a sentence is
    /// recognized as covering the matching suggestion without the user doing anything extra.
    public static let defaults: [ChecklistSuggestion] = [
        ChecklistSuggestion(id: "passport", titleKey: "checklist.passport", category: .travel, suggestedRecurrence: .none, systemImage: "airplane", matchKeywords: ["passport", "דרכון", "pasaporte", "passeport"]),
        ChecklistSuggestion(id: "driverLicense", titleKey: "checklist.driverLicense", category: .documents, suggestedRecurrence: .none, systemImage: "person.text.rectangle", matchKeywords: ["driver's license", "drivers license", "רישיון נהיגה", "licencia de conducir", "permis de conduire"]),
        ChecklistSuggestion(id: "carInsurance", titleKey: "checklist.carInsurance", category: .insurance, suggestedRecurrence: .yearly, systemImage: "car.fill", matchKeywords: ["car insurance", "ביטוח רכב", "seguro de auto", "seguro de coche", "assurance auto", "assurance voiture"]),
        ChecklistSuggestion(id: "homeInsurance", titleKey: "checklist.homeInsurance", category: .insurance, suggestedRecurrence: .yearly, systemImage: "house.fill", matchKeywords: ["home insurance", "ביטוח דירה", "ביטוח בית", "seguro de hogar", "seguro de casa", "assurance habitation", "assurance maison"]),
        ChecklistSuggestion(id: "healthInsurance", titleKey: "checklist.healthInsurance", category: .insurance, suggestedRecurrence: .yearly, systemImage: "heart.fill", matchKeywords: ["health insurance", "ביטוח בריאות", "seguro de salud", "assurance santé"]),
        ChecklistSuggestion(id: "lifeInsurance", titleKey: "checklist.lifeInsurance", category: .insurance, suggestedRecurrence: .yearly, systemImage: "shield.fill", matchKeywords: ["life insurance", "ביטוח חיים", "seguro de vida", "assurance vie"]),
        ChecklistSuggestion(id: "rentOrMortgage", titleKey: "checklist.rentOrMortgage", category: .bills, suggestedRecurrence: .monthly, systemImage: "house.fill", matchKeywords: ["rent", "mortgage", "שכר דירה", "שכירות", "משכנתא", "alquiler", "renta", "hipoteca", "loyer", "hypothèque"]),
        ChecklistSuggestion(id: "carRegistration", titleKey: "checklist.carRegistration", category: .car, suggestedRecurrence: .yearly, systemImage: "car.fill", matchKeywords: ["car registration", "רישוי רכב", "טסט רכב"]),
        ChecklistSuggestion(id: "propertyTax", titleKey: "checklist.propertyTax", category: .bills, suggestedRecurrence: .none, systemImage: "building.columns.fill", matchKeywords: ["property tax", "ארנונה"]),
        ChecklistSuggestion(id: "willOrPOA", titleKey: "checklist.willOrPOA", category: .documents, suggestedRecurrence: .none, systemImage: "doc.text.fill", matchKeywords: ["will", "power of attorney", "צוואה", "ייפוי כוח"]),
        ChecklistSuggestion(id: "petInsurance", titleKey: "checklist.petInsurance", category: .insurance, suggestedRecurrence: .yearly, systemImage: "pawprint.fill", matchKeywords: ["pet insurance", "ביטוח חיות מחמד"]),
        ChecklistSuggestion(id: "travelInsurance", titleKey: "checklist.travelInsurance", category: .insurance, suggestedRecurrence: .none, systemImage: "airplane", matchKeywords: ["travel insurance", "ביטוח נסיעות", "seguro de viaje", "assurance voyage"]),
        ChecklistSuggestion(id: "gymMembership", titleKey: "checklist.gymMembership", category: .memberships, suggestedRecurrence: .monthly, systemImage: "figure.run", matchKeywords: ["gym", "חדר כושר", "gimnasio", "salle de sport"]),
        ChecklistSuggestion(id: "idCard", titleKey: "checklist.idCard", category: .documents, suggestedRecurrence: .none, systemImage: "person.text.rectangle", matchKeywords: ["id card", "תעודת זהות"]),
        ChecklistSuggestion(id: "visa", titleKey: "checklist.visa", category: .travel, suggestedRecurrence: .none, systemImage: "airplane", matchKeywords: ["visa", "ויזה"]),
        ChecklistSuggestion(id: "homeWarranty", titleKey: "checklist.homeWarranty", category: .warranties, suggestedRecurrence: .none, systemImage: "checkmark.seal.fill", matchKeywords: ["warranty", "אחריות", "garantía", "garantie"]),
        ChecklistSuggestion(id: "creditCardAnnualFee", titleKey: "checklist.creditCardAnnualFee", category: .money, suggestedRecurrence: .yearly, systemImage: "creditcard.fill", matchKeywords: ["credit card", "כרטיס אשראי", "tarjeta de crédito", "carte de crédit"])
    ]
}

/// Decides which checklist suggestions the user still needs to act on.
public struct ChecklistEngine: Sendable {
    public init() {}

    /// A suggestion counts as covered by any active (or snoozed) item sharing its category — and,
    /// when the suggestion lists keywords (needed to tell "car insurance" apart from "home
    /// insurance", both `.insurance`), by one of those keywords actually appearing in that item's
    /// title. A `.completed` item does NOT count, alongside the already-excluded `.archived`:
    /// for a recurring suggestion (car insurance renews yearly) completing it immediately creates
    /// a fresh active occurrence via `RecurrenceEngine.nextOccurrence`, so coverage never actually
    /// lapses — but a one-off suggestion (`suggestedRecurrence: .none`, e.g. passport, ID card,
    /// will) has no next occurrence to fall back on, and treating its now-completed, never-to-
    /// recur item as still "covering" it would mean the checklist can never again ask about
    /// renewing a passport that expired years ago.
    public func isCovered(_ suggestion: ChecklistSuggestion, by items: [LifeAdminItem]) -> Bool {
        items.contains { item in
            guard item.status == .active || item.status == .snoozed, item.category == suggestion.category else { return false }
            guard suggestion.matchKeywords.isEmpty == false else { return true }
            let title = item.title.lowercased()
            return suggestion.matchKeywords.contains { title.contains($0) }
        }
    }

    /// Suggestions still worth showing: not already covered by an existing item, and not one the
    /// user explicitly dismissed as not relevant to them (no car, no pet, renting rather than
    /// owning, ...) — dismissing one must be permanent, or the checklist would keep nagging about
    /// something the user already said doesn't apply.
    public func outstandingSuggestions(from all: [ChecklistSuggestion] = ChecklistSuggestion.defaults, items: [LifeAdminItem], dismissedIDs: Set<String> = []) -> [ChecklistSuggestion] {
        all.filter { dismissedIDs.contains($0.id) == false && isCovered($0, by: items) == false }
    }
}
