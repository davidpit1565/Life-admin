import SwiftUI
import ContactsUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import LifeAdminCore

struct ItemDetailView: View {
    @EnvironmentObject var store: ItemStore
    @Environment(\.dismiss) var dismiss
    let item: LifeAdminItem
    // True only for a checklist-suggested draft that has never been written to SwiftData yet
    // (see `ItemStore.draftItem(for:)`) — lets `save()`/`markDone()` persist it for the first
    // time instead of updating an item that doesn't exist in `store.items` yet.
    let isNewDraft: Bool

    @State private var title: String
    @State private var category: LifeCategory
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var recurrence: Recurrence
    @State private var amountText: String
    @State private var currency: String
    @State private var notes: String
    @State private var name: String
    @State private var company: String
    @State private var email: String
    @State private var phone: String
    @State private var attachments: [Attachment]
    @State private var showingContactPicker = false
    @State private var showingDeleteConfirmation = false
    @State private var isSaving = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showingFileImporter = false
    @State private var isImportingAttachment = false
    // Set right before any of save()/markDone()/reopen()/the Delete confirmation actually
    // commits — lets `.onDisappear` below tell "the user finished with this screen" apart from
    // "the user swiped it away", so it only cleans up abandoned attachment files in the latter
    // case (see `discardAbandonedAttachments`).
    @State private var didFinish = false
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Reset every time this view is freshly opened (a new instance, a new empty Set) rather than
    // persisted anywhere — a photographed passport or insurance card should ask again next time
    // the item is opened, not stay revealed forever once unlocked once.
    @State private var revealedAttachmentIDs: Set<UUID> = []

    init(item: LifeAdminItem, isNewDraft: Bool = false) {
        self.item = item
        self.isNewDraft = isNewDraft
        _title = State(initialValue: item.title)
        _category = State(initialValue: item.category)
        _hasDueDate = State(initialValue: item.dueDate != nil)
        _dueDate = State(initialValue: item.dueDate ?? Date())
        _recurrence = State(initialValue: item.recurrence)
        _amountText = State(initialValue: item.amount.map { "\($0)" } ?? "")
        _currency = State(initialValue: item.currency ?? "")
        _notes = State(initialValue: item.notes ?? "")
        _name = State(initialValue: item.contact?.name ?? "")
        _company = State(initialValue: item.contact?.company ?? "")
        _email = State(initialValue: item.contact?.email ?? "")
        _phone = State(initialValue: item.contact?.phone ?? "")
        _attachments = State(initialValue: item.attachments)
    }

    var body: some View {
        Form {
            // A heuristic, not a guarantee (see NaturalLanguageParser.detectsScamLanguage) — the
            // wording says "double-check", not "this is a scam", since it can be wrong in both
            // directions.
            if item.tags.contains(NaturalLanguageParser.scamRiskTag) {
                Section {
                    Label(String(localized: "itemDetail.scamWarning"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            Section(String(localized: "itemDetail.details")) {
                TextField(String(localized: "itemDetail.title"), text: $title)
                Picker(String(localized: "itemDetail.category"), selection: $category) {
                    ForEach(LifeCategory.allCases, id: \.self) { cat in
                        Label(cat.displayName, systemImage: cat.symbolName).tag(cat)
                    }
                }
            }

            Section(String(localized: "itemDetail.dueDate")) {
                Toggle(String(localized: "itemDetail.hasDueDate"), isOn: $hasDueDate.animation(reduceMotion ? nil : .default))
                if hasDueDate {
                    DatePicker(String(localized: "itemDetail.dueDate"), selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    // Recurrence with no due date to recur from is exactly the same trap as
                    // .custom above: RecurrenceEngine.nextOccurrence requires a dueDate, so
                    // "Repeat: Monthly" on an item with no due date would silently never fire —
                    // gating this alongside the date picker keeps it from ever being offered
                    // without the one thing it needs to mean anything.
                    Picker(String(localized: "itemDetail.recurrence"), selection: $recurrence) {
                        // .custom is excluded deliberately: there's no UI anywhere to actually
                        // define a custom rule, and RecurrenceEngine treats it exactly like .none
                        // (never recurs) — offering it would let someone pick "Custom", assume
                        // they've set up a schedule, and never find out it silently does nothing.
                        ForEach(Recurrence.allCases.filter { $0 != .custom }, id: \.self) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    // Committing to "every month" sight-unseen is a leap of faith — showing where
                    // it actually lands lets someone catch a wrong choice (e.g. weekly instead of
                    // biweekly) before saving, instead of discovering it three occurrences later.
                    if recurrence != .none, upcomingOccurrences.isEmpty == false {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "itemDetail.recurrence.preview"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(upcomingOccurrences.map { $0.formatted(date: .abbreviated, time: .omitted) }.joined(separator: "  •  "))
                                .font(.caption)
                        }
                    }
                }
            }

            Section(String(localized: "itemDetail.amount")) {
                TextField(String(localized: "itemDetail.amount"), text: $amountText)
                    .keyboardType(.decimalPad)
                // A renewal quietly costing more than last time is exactly the kind of thing
                // this app exists to catch — surfaced right where the number is being looked at,
                // not buried somewhere it'd only be found by comparing old records by hand.
                if let priceChangeDescription {
                    Text(priceChangeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // A free-text currency field meant typing a typo (or the wrong case) silently
                // dropped the whole currency on save with zero explanation — Locale.commonISOCurrencyCodes
                // doesn't match "usd" or "dolars". A picker can't produce an invalid value at all.
                // currencyOptions always includes whatever this item already has, even if it's
                // outside the common four, so an AI-detected currency never disappears just from
                // opening this screen.
                Picker(String(localized: "itemDetail.currency"), selection: $currency) {
                    Text(String(localized: "itemDetail.currency.none")).tag("")
                    ForEach(currencyOptions, id: \.self) { code in
                        Text(currencyLabel(code)).tag(code)
                    }
                }
            }

            Section {
                Button {
                    showingContactPicker = true
                } label: {
                    Label(String(localized: "editContact.chooseFromContacts"), systemImage: "person.crop.circle.badge.plus")
                }
            }
            Section(String(localized: "editContact.section")) {
                TextField(String(localized: "editContact.name"), text: $name)
                TextField(String(localized: "editContact.company"), text: $company)
                TextField(String(localized: "editContact.email"), text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                // "Call customer service" is one of the single most common follow-ups on a bill or
                // insurance item — a phone field with no way to actually place the call from here
                // would just mean copy-pasting the number into the Phone app anyway.
                HStack {
                    TextField(String(localized: "editContact.phone"), text: $phone)
                        .keyboardType(.phonePad)
                    if let callURL {
                        Link(destination: callURL) {
                            Image(systemName: "phone.fill")
                        }
                        .accessibilityLabel(String(localized: "editContact.call"))
                    }
                }
            }

            Section(String(localized: "itemDetail.notes")) {
                TextEditor(text: $notes).frame(minHeight: 80)
            }

            // Always shown, even with nothing attached yet — the document scanner (VisionKit +
            // on-device OCR) that could once add the first attachment is held back behind a
            // feature flag for App Store review reasons, so without a picker here an item like a
            // checklist-created "Passport" reminder would have no way at all to actually attach
            // the passport photo it exists to hold.
            Section(String(localized: "itemDetail.attachments")) {
                if attachments.isEmpty == false {
                    ForEach(attachments) { attachment in
                        HStack {
                            if let uiImage = UIImage(contentsOfFile: AttachmentStore.shared.url(for: attachment).path) {
                                // Only actually gates anything when the user opted into App Lock —
                                // requiring Face ID to see a photo in an app that otherwise has no
                                // lock at all would be a jarring, unexplained inconsistency rather
                                // than an extra layer of the security they already asked for.
                                let isRevealed = appLockEnabled == false || revealedAttachmentIDs.contains(attachment.id)
                                Image(uiImage: uiImage).resizable().scaledToFill()
                                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                                    .blur(radius: isRevealed ? 0 : 12)
                                    .overlay {
                                        if isRevealed == false {
                                            Image(systemName: "lock.fill")
                                                .foregroundStyle(.white)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        guard isRevealed == false else { return }
                                        Task {
                                            // A device that can't verify identity at all (no
                                            // passcode set) must never be treated as "revealed" —
                                            // the same nil-handling rule AppLockService's own
                                            // documentation calls for everywhere else it's used.
                                            if await AppLockService.shared.authenticate() == true {
                                                revealedAttachmentIDs.insert(attachment.id)
                                            }
                                        }
                                    }
                                    .accessibilityLabel(isRevealed ? Text(attachment.filename) : Text(String(localized: "itemDetail.attachmentLocked")))
                                    .accessibilityAddTraits(isRevealed ? [] : .isButton)
                            } else {
                                Image(systemName: "doc.fill").foregroundStyle(.secondary)
                            }
                            Text(attachment.filename)
                        }
                    }
                    .onDelete { offsets in
                        // Only remove from this screen's own draft state here — the file on disk
                        // isn't deleted until Save/Mark Done actually commits the change (see
                        // deleteFilesForRemovedAttachments()). Deleting it immediately meant
                        // backing out without saving still permanently destroyed the photo, unlike
                        // every other edit on this screen (title, notes, category, …), which stays
                        // safely discardable until Save is tapped.
                        attachments.remove(atOffsets: offsets)
                    }
                }
                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 5, matching: .images) {
                    Label(String(localized: "itemDetail.addPhoto"), systemImage: "photo.on.rectangle")
                }
                .disabled(isImportingAttachment)
                Button {
                    showingFileImporter = true
                } label: {
                    Label(String(localized: "itemDetail.browseFiles"), systemImage: "folder")
                }
                .disabled(isImportingAttachment)
                // A multi-second delay with zero feedback while a large photo/PDF is read, size-
                // checked, and written through AttachmentStore would otherwise look exactly like
                // the tap silently didn't register — the same reasoning behind every other
                // isSaving-style spinner already in this screen and AddItemView's Save button.
                if isImportingAttachment {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "itemDetail.addingAttachment"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if item.status == .active {
                Section {
                    Button {
                        isSaving = true
                        Task {
                            await markDone()
                            dismiss()
                        }
                    } label: {
                        Label(String(localized: "itemDetail.markDone"), systemImage: "checkmark.circle.fill")
                    }
                    .disabled(isSaving)
                    // Only meaningful with a due date to push forward — the notification banner's
                    // own "Snooze" button always adds a fixed 1 day; this gives the same idea a
                    // few real durations from inside the item itself.
                    if hasDueDate {
                        Menu {
                            ForEach(Self.snoozeOptions) { option in
                                Button(option.label) {
                                    isSaving = true
                                    Task {
                                        // Snoozing an already-overdue item from its own stale due
                                        // date can still land in the past (e.g. 10 days overdue,
                                        // +1 day snooze = 9 days overdue) — snoozing from "now"
                                        // guarantees a real future date the reminder can fire on.
                                        let base = max(dueDate, Date())
                                        dueDate = Calendar.current.date(byAdding: .day, value: option.days, to: base) ?? dueDate
                                        await save()
                                        dismiss()
                                    }
                                }
                            }
                        } label: {
                            Label(String(localized: "itemDetail.snooze"), systemImage: "clock.arrow.circlepath")
                        }
                        .disabled(isSaving)
                    }
                }
            } else if item.status == .completed {
                // A fat-fingered "Mark Done" (or simply changing your mind) otherwise had no way
                // back except Delete — permanently losing the item instead of just undoing a
                // status change. Reopening goes through the same `save()`/store.update path as
                // every other edit, so it also correctly re-schedules a reminder if there's still
                // a due date, rather than leaving the item active but silently unreminded.
                Section {
                    Button {
                        isSaving = true
                        Task {
                            await reopen()
                            dismiss()
                        }
                    } label: {
                        Label(String(localized: "itemDetail.reopen"), systemImage: "arrow.uturn.backward.circle.fill")
                    }
                    .disabled(isSaving)
                }
            }

            Section {
                Button {
                    isSaving = true
                    Task {
                        await save()
                        dismiss()
                    }
                } label: {
                    // Save/Mark Done/Snooze all call the same async store methods as AddItemView's
                    // Save button, which already learned this lesson: with nothing disabled and no
                    // feedback, a second tap before the first finishes fires a second concurrent
                    // write, and a slow save just looks like the tap did nothing at all.
                    if isSaving {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(String(localized: "common.save"))
                        }
                    } else {
                        Text(String(localized: "common.save"))
                    }
                }
                .disabled(isSaving)
                Button(String(localized: "itemDetail.delete"), role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle(title.isEmpty ? item.title : title)
        // Every attachment source here (Photos, Files, the document scanner) writes its file to
        // disk the moment it's picked, same timing as AddItemView's own scanner — swiping this
        // whole screen away instead of tapping Save/Mark Done/Delete would otherwise leave that
        // file behind forever with nothing left pointing at it.
        .onDisappear {
            guard didFinish == false else { return }
            discardAbandonedAttachments()
        }
        .sheet(isPresented: $showingContactPicker) {
            ContactPickerView { contact in
                apply(contact)
            }
        }
        .sheet(isPresented: $showingFileImporter) {
            FileImportPicker(
                onPicked: { url in
                    isImportingAttachment = true
                    Task {
                        await addAttachment(fromFileAt: url)
                        isImportingAttachment = false
                    }
                },
                onCancel: { showingFileImporter = false }
            )
        }
        // Each selected library photo is written to disk (via AttachmentStore, immediately —
        // same timing as the document scanner's own pendingAttachments) the moment it's picked,
        // same as every other attachment source; only the item's `attachments` array itself
        // waits for Save, exactly like the existing swipe-to-remove above.
        .onChange(of: selectedPhotoItems) { _, newItems in
            guard newItems.isEmpty == false else { return }
            let itemsToLoad = newItems
            selectedPhotoItems = []
            isImportingAttachment = true
            Task {
                for photoItem in itemsToLoad {
                    await addAttachment(from: photoItem)
                }
                isImportingAttachment = false
            }
        }
        .confirmationDialog(
            String(localized: "itemDetail.deleteConfirm"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "itemDetail.delete"), role: .destructive) {
                Task {
                    await store.delete(item)
                    dismiss()
                }
            }
        }
    }

    private static let commonCurrencyCodes = ["USD", "EUR", "ILS", "GBP"]

    private struct SnoozeOption: Identifiable { let days: Int; let label: String; var id: Int { days } }

    private static let snoozeOptions: [SnoozeOption] = [
        SnoozeOption(days: 1, label: String(localized: "itemDetail.snooze.1day")),
        SnoozeOption(days: 3, label: String(localized: "itemDetail.snooze.3days")),
        SnoozeOption(days: 7, label: String(localized: "itemDetail.snooze.1week"))
    ]

    /// A renewal costing more than the cycle it replaced — RecurrenceEngine.nextOccurrence carries
    /// the prior amount forward specifically so this can be caught, rather than a price increase
    /// quietly blending into "just this year's number". Reads the live, still-being-edited
    /// `amountText` (not `item.amount`) so typing in the new renewal price updates this
    /// immediately, before Save.
    private var priceChangeDescription: String? {
        guard let previous = item.previousAmount, previous != 0,
              let current = Decimal(string: amountText.trimmingCharacters(in: .whitespacesAndNewlines), locale: Locale.current),
              current != previous else { return nil }
        let percent = Double(truncating: ((current - previous) / previous * 100) as NSDecimalNumber)
        let roundedPercent = abs(Int(percent.rounded()))
        return percent > 0
            ? String(format: String(localized: "itemDetail.priceIncreased"), roundedPercent)
            : String(format: String(localized: "itemDetail.priceDecreased"), roundedPercent)
    }

    /// The next 3 dates this recurrence would actually land on, chained from the current due
    /// date — reuses RecurrenceEngine.nextDueDate directly rather than a second implementation
    /// of the same schedule math that could quietly drift out of sync with it. The anchor day is
    /// fixed once from the due date shown here, not re-derived from each chained date in turn —
    /// otherwise a monthly recurrence anchored on the 31st would clamp to the 30th at the first
    /// short month and never show the 31st again, the same drift RecurrenceEngine itself guards
    /// against for the item's real, persisted occurrences.
    private var upcomingOccurrences: [Date] {
        var dates: [Date] = []
        var current = dueDate
        let anchorDay = Calendar.current.component(.day, from: dueDate)
        for _ in 0..<3 {
            guard let next = RecurrenceEngine().nextDueDate(after: current, recurrence: recurrence, anchorDay: anchorDay) else { break }
            dates.append(next)
            current = next
        }
        return dates
    }

    private var currencyOptions: [String] {
        var options = Self.commonCurrencyCodes
        if currency.isEmpty == false && options.contains(currency) == false {
            options.append(currency)
        }
        return options
    }

    private func currencyLabel(_ code: String) -> String {
        guard let name = Locale.current.localizedString(forCurrencyCode: code) else { return code }
        // A Latin currency code stitched to a Hebrew/Arabic name with a plain dash is exactly the
        // mixed-direction case that makes the dash (and whatever follows it) jump to the wrong
        // side — wrapping the code in explicit directional isolates keeps it as a self-contained
        // LTR run no matter which way the rest of the string flows.
        let isolatedCode = "\u{2066}\(code)\u{2069}"
        return "\(isolatedCode) – \(name)"
    }

    /// `nil` for anything empty or that doesn't produce a valid `tel:` URL — the tap-to-call
    /// button itself is only shown when this is non-nil, so a garbled or empty phone field just
    /// silently has no call button rather than one that fails when tapped.
    private var callURL: URL? {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return URL(string: "tel:\(trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed)")
    }

    private func apply(_ contact: CNContact) {
        let fullName = [contact.givenName, contact.familyName].filter { $0.isEmpty == false }.joined(separator: " ")
        if fullName.isEmpty == false { name = fullName }
        if contact.organizationName.isEmpty == false { company = contact.organizationName }
        if let firstEmail = contact.emailAddresses.first?.value as String? { email = firstEmail }
        if let firstPhone = contact.phoneNumbers.first?.value.stringValue, firstPhone.isEmpty == false { phone = firstPhone }
    }

    private func fieldsApplied(to base: LifeAdminItem) -> LifeAdminItem {
        var updated = base
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmedTitle.isEmpty ? base.title : trimmedTitle
        updated.category = category
        updated.dueDate = hasDueDate ? dueDate : nil
        // Recurrence is meaningless without a due date to recur from — the picker itself is
        // already hidden in that case, but the state variable could otherwise still hold a
        // stale value from before "Has due date" was turned off.
        updated.recurrence = hasDueDate ? recurrence : .none
        // Re-derived from whatever due date is on screen right now rather than left as
        // whatever it was on `base` — otherwise editing an existing recurring item's due date
        // to a different day of the month would silently keep recurring on the OLD day, since
        // RecurrenceEngine only re-derives this itself the first time it's nil.
        updated.recurrenceAnchorDay = hasDueDate ? Calendar.current.component(.day, from: dueDate) : nil
        // .decimalPad shows the device's own locale-appropriate separator (e.g. "," in many
        // European locales) — parsing with Decimal(string:) alone only ever accepts ".", silently
        // dropping the amount entirely for anyone whose keyboard shows anything else.
        updated.amount = Decimal(string: amountText.trimmingCharacters(in: .whitespacesAndNewlines), locale: Locale.current)
        // currency is a Picker now (see currencyOptions) — it can only ever hold "" or a code
        // that's either one of the common four or the item's own pre-existing value, so there's
        // nothing left here to trim, uppercase, or validate.
        updated.currency = currency.isEmpty ? nil : currency
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        updated.attachments = attachments
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCompany = company.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.contact = (trimmedName.isEmpty && trimmedCompany.isEmpty && trimmedEmail.isEmpty && trimmedPhone.isEmpty) ? nil : ContactInfo(
            name: trimmedName.isEmpty ? nil : trimmedName,
            company: trimmedCompany.isEmpty ? nil : trimmedCompany,
            phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail
        )
        updated.updatedAt = Date()
        return updated
    }

    // `item` is only ever the snapshot this view was created with — if a notification action
    // (e.g. "Mark Done" tapped on this same item's own banner) mutates the store while this
    // screen is still open, building on that stale snapshot would silently overwrite whatever
    // just happened (reviving a just-completed item back to active, dropping a snooze) the
    // moment this screen's own Save/Mark Done runs. Basing edits on the store's current copy
    // instead means only fields this form actually touches change; anything else reflects
    // whatever most recently happened elsewhere.
    private var currentItem: LifeAdminItem {
        store.items.first(where: { $0.id == item.id }) ?? item
    }

    /// Deletes the on-disk file for any attachment the user swiped away on this screen — deferred
    /// until here (rather than at the moment of the swipe) so the removal only actually happens
    /// once it's committed via Save/Mark Done, matching every other edit on this form.
    private func deleteFilesForRemovedAttachments() {
        let removed = item.attachments.filter { attachments.contains($0) == false }
        for attachment in removed {
            AttachmentStore.shared.delete(attachment)
        }
    }

    /// The mirror image of `deleteFilesForRemovedAttachments`: cleans up on-disk files for
    /// attachments that aren't actually committed anywhere, because the screen was dismissed some
    /// other way than Save/Mark Done/Delete. Deliberately compares against what's REALLY currently
    /// persisted (`store.items`), not `item.attachments` (this view's initial snapshot): for an
    /// `isNewDraft` item — or a checklist/"ask every time" merge preview, whose `item.attachments`
    /// already includes files an eventual Save would add but a real update() hasn't applied yet —
    /// nothing in `item.attachments` is actually safe on its own. A never-persisted draft has no
    /// entry in `store.items` at all, so every current attachment counts as abandoned; an existing
    /// item being edited keeps only its real stored attachments as the safe baseline.
    private func discardAbandonedAttachments() {
        let committedAttachments = store.items.first(where: { $0.id == item.id })?.attachments ?? []
        let abandoned = attachments.filter { committedAttachments.contains($0) == false }
        for attachment in abandoned {
            AttachmentStore.shared.delete(attachment)
        }
    }

    /// Neither picker enforces a size limit of its own — an accidentally-selected multi-page PDF
    /// scan or a RAW/ProRes-adjacent photo could otherwise load tens or hundreds of megabytes
    /// fully into memory (`Data(contentsOf:)`/`loadTransferable` both read the whole file at
    /// once) for something that only ever needs to hold a passport photo or a policy PDF. 25 MB
    /// comfortably fits any real document or photo this app's use case involves.
    private static let maxAttachmentBytes = 25 * 1024 * 1024

    /// A library photo's `supportedContentTypes` reflects whatever the source file actually is
    /// (often HEIC on a modern iPhone, not JPEG) — reading that instead of assuming JPEG keeps
    /// both the saved bytes and their declared mimeType/extension honest about the real format.
    private func addAttachment(from photoItem: PhotosPickerItem) async {
        guard let data = try? await photoItem.loadTransferable(type: Data.self), data.count <= Self.maxAttachmentBytes else { return }
        let contentType = photoItem.supportedContentTypes.first
        let fileExtension = contentType?.preferredFilenameExtension ?? "jpg"
        let mimeType = contentType?.preferredMIMEType ?? "image/jpeg"
        let filename = String(format: String(localized: "itemDetail.photoFilename"), attachments.count + 1)
        if let attachment = AttachmentStore.shared.save(data: data, filename: filename, mimeType: mimeType, fileExtension: fileExtension) {
            attachments.append(attachment)
            await autoFillFromImageAttachment(attachment)
        }
    }

    /// `FileImportPicker` hands back a URL to a local copy already inside this app's sandbox
    /// (`asCopy: true`), so this only needs to read it and hand the bytes to the same
    /// `AttachmentStore` every other attachment source goes through. That copy lives outside
    /// `AttachmentStore`'s own protected, backup-excluded directory (it's the system's plain,
    /// unprotected /tmp), so it's removed here the moment its bytes are safely persisted through
    /// AttachmentStore, rather than left for the system to eventually reclaim on its own schedule.
    private func addAttachment(fromFileAt url: URL) async {
        showingFileImporter = false
        defer { try? FileManager.default.removeItem(at: url) }
        // Checked from the file's own metadata BEFORE reading its bytes — a multi-hundred-MB file
        // picked from a cloud provider through Files (nothing stops someone from picking a large
        // video renamed to .pdf) would otherwise be fully loaded into memory by `Data(contentsOf:)`
        // itself before this guard ever got a chance to reject it.
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        guard let fileSize, fileSize <= Self.maxAttachmentBytes else { return }
        guard let data = try? Data(contentsOf: url), data.count <= Self.maxAttachmentBytes else { return }
        let fileExtension = url.pathExtension.isEmpty ? "dat" : url.pathExtension
        let mimeType = UTType(filenameExtension: fileExtension)?.preferredMIMEType ?? "application/octet-stream"
        if let attachment = AttachmentStore.shared.save(data: data, filename: Self.sanitizedFilename(url.lastPathComponent), mimeType: mimeType, fileExtension: fileExtension) {
            attachments.append(attachment)
            await autoFillFromImageAttachment(attachment)
        }
    }

    /// A photo of a passport, an insurance card, or any other document is otherwise just a
    /// picture sitting in the attachments list — someone still has to read it themselves and
    /// retype the title/category/date/amount by hand. Running the same on-device OCR the camera
    /// scanner already uses, then handing the recognized text through the exact same
    /// AI-Autonomy-respecting extraction pipeline as typed input, means attaching the photo is
    /// often enough on its own. Never touches a field the user (or an earlier auto-fill) already
    /// put something into — this is "fill in the blanks," not "trust the photo over what's
    /// already on screen." PDFs are skipped: Vision's text recognition reads image pixels, not a
    /// PDF's text layer, so running it against page 1 of a multi-page PDF would silently ignore
    /// the rest and likely mislead more than it'd help.
    private func autoFillFromImageAttachment(_ attachment: Attachment) async {
        guard attachment.mimeType.hasPrefix("image/"),
              let uiImage = UIImage(contentsOfFile: AttachmentStore.shared.url(for: attachment).path) else { return }
        let recognizedText = await Task.detached(priority: .userInitiated) {
            TextRecognizer.recognizeText(in: uiImage)
        }.value
        guard recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        let extracted = await store.extractFields(from: recognizedText)
        applyAutoFill(extracted)
    }

    private func applyAutoFill(_ extracted: ExtractedItem) {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let extractedTitle = extracted.title, extractedTitle.isEmpty == false {
            title = extractedTitle
        }
        if category == .other, let extractedCategory = extracted.category {
            category = extractedCategory
        }
        if hasDueDate == false, let date = extracted.date {
            hasDueDate = true
            dueDate = date
        }
        if amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let amount = extracted.amount {
            amountText = "\(amount)"
        }
        if currency.isEmpty, let extractedCurrency = extracted.currency {
            currency = extractedCurrency
        }
    }

    /// A file from an external Files provider carries whatever name its source gave it —
    /// including, in principle, Unicode bidi-override characters (U+202A–U+202E, U+2066–U+2069)
    /// that could make a name display as something other than what it actually is (the classic
    /// "invoice\u{202E}fdp.exe" trick, which reads as "invoice...exe.pdf"). This is purely a
    /// display concern — `Attachment.filename` is never executed or used as a real file path (see
    /// `AttachmentStore.url(for:)`, which always stores under a fresh UUID) — but there's no
    /// reason to let a misleading name reach the UI as-is.
    private static func sanitizedFilename(_ raw: String) -> String {
        let filtered = raw.unicodeScalars.filter {
            !($0.value >= 0x202A && $0.value <= 0x202E) && !($0.value >= 0x2066 && $0.value <= 0x2069)
        }
        return String(String.UnicodeScalarView(filtered))
    }

    private func save() async {
        didFinish = true
        deleteFilesForRemovedAttachments()
        let before = currentItem
        var updated = fieldsApplied(to: before)
        updated.priority = PriorityEngine().priority(for: updated)
        if isNewDraft {
            _ = await store.persistNewItem(updated)
        } else {
            logPriceChangeIfNeeded(before: before, after: updated)
            await store.update(updated)
        }
    }

    /// Until now, a renewal costing more than last time was only ever visible by reopening this
    /// exact edit screen and reading `priceChangeDescription` above — nowhere else in the app
    /// (the item list row aside) recorded that it happened at all. Logging it here, keyed to the
    /// edit that actually introduces the new amount rather than to `previousAmount`/`amount`
    /// simply differing, means re-saving the same item again and again without touching the
    /// amount doesn't write the same "price changed" entry into the log every time.
    private func logPriceChangeIfNeeded(before: LifeAdminItem, after: LifeAdminItem) {
        guard before.amount != after.amount, let percent = RecurrenceEngine().priceChangePercent(for: after) else { return }
        let rounded = Int(percent.rounded())
        guard rounded != 0 else { return }
        ActivityLog.shared.record(String(format: String(localized: "activityLog.priceChanged"), rounded, after.title))
    }

    private func markDone() async {
        didFinish = true
        deleteFilesForRemovedAttachments()
        var updated = fieldsApplied(to: currentItem)
        updated.priority = PriorityEngine().priority(for: updated)
        if isNewDraft {
            // Persist first (so the item actually exists in `store.items`), then run it through
            // the same `markCompleted` every other "mark done" path uses — that's what schedules
            // the next occurrence for a recurring checklist item (e.g. a suggested monthly bill)
            // instead of duplicating that logic here.
            let persisted = await store.persistNewItem(updated)
            await store.markCompleted(persisted)
        } else {
            await store.markCompleted(updated)
        }
    }

    private func reopen() async {
        didFinish = true
        deleteFilesForRemovedAttachments()
        var updated = fieldsApplied(to: currentItem)
        updated.status = .active
        updated.priority = PriorityEngine().priority(for: updated)
        await store.update(updated)
    }
}
