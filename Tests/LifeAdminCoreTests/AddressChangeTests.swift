import XCTest
@testable import LifeAdminCore

final class AddressChangeTests: XCTestCase {
    func testAffectedItemsIncludesOnlyItemsWithContactEmail() {
        let withEmail = LifeAdminItem(title: "Car Insurance", contact: ContactInfo(name: "Dana", email: "dana@insurer.example"))
        let withoutEmail = LifeAdminItem(title: "Gym Membership")
        let affected = AddressChangeEngine().affectedItems(in: [withEmail, withoutEmail])
        XCTAssertEqual(affected.map(\.id), [withEmail.id])
    }

    func testAffectedItemsExcludesAlreadySyncedItems() {
        var item = LifeAdminItem(title: "Car Insurance", contact: ContactInfo(email: "dana@insurer.example"))
        item.tags = [AddressChangeEngine.syncedTag]
        XCTAssertTrue(AddressChangeEngine().affectedItems(in: [item]).isEmpty)
    }

    func testAffectedItemsTreatsEmptyEmailAsMissing() {
        let item = LifeAdminItem(title: "Gym Membership", contact: ContactInfo(name: "Dana", email: ""))
        XCTAssertTrue(AddressChangeEngine().affectedItems(in: [item]).isEmpty)
    }

    func testDraftBuilderProducesRecipientSubjectAndBody() {
        let item = LifeAdminItem(title: "Car Insurance", contact: ContactInfo(name: "Dana", company: "SafeDrive", email: "dana@insurer.example"))
        let message = AddressChangeDraftBuilder().draft(for: item, newAddress: "12 Herzl St, Tel Aviv")
        XCTAssertEqual(message?.recipientEmail, "dana@insurer.example")
        XCTAssertEqual(message?.recipientName, "Dana")
        XCTAssertEqual(message?.itemID, item.id)
        XCTAssertTrue(message?.subject.contains("Car Insurance") == true)
        XCTAssertTrue(message?.body.contains("12 Herzl St, Tel Aviv") == true)
    }

    func testDraftBuilderFallsBackToCompanyNameWhenNoContactName() {
        let item = LifeAdminItem(title: "Car Insurance", contact: ContactInfo(company: "SafeDrive", email: "claims@safedrive.example"))
        let message = AddressChangeDraftBuilder().draft(for: item, newAddress: "12 Herzl St")
        XCTAssertEqual(message?.recipientName, "SafeDrive")
    }

    func testDraftBuilderReturnsNilWithoutContactEmail() {
        let item = LifeAdminItem(title: "Gym Membership")
        XCTAssertNil(AddressChangeDraftBuilder().draft(for: item, newAddress: "12 Herzl St"))
    }

    func testDraftsFiltersToItemsWithEmailOnly() {
        let withEmail = LifeAdminItem(title: "Car Insurance", contact: ContactInfo(email: "dana@insurer.example"))
        let withoutEmail = LifeAdminItem(title: "Gym Membership")
        let messages = AddressChangeDraftBuilder().drafts(for: [withEmail, withoutEmail], newAddress: "12 Herzl St")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.itemID, withEmail.id)
    }
}
