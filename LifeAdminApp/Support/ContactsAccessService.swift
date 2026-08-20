import Contacts

struct ContactsAccessService {
    static let shared = ContactsAccessService()

    func requestAuthorizationIfNeeded() async {
        guard CNContactStore.authorizationStatus(for: .contacts) == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            CNContactStore().requestAccess(for: .contacts) { _, _ in
                continuation.resume()
            }
        }
    }
}
