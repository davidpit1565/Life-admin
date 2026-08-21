import Foundation
import UIKit
import LifeAdminCore

/// Persists scanned/attached files to the app's own Application Support directory so an
/// `Attachment`'s `localPath` points at a file that actually exists on disk, and removes that
/// file again on delete — without this, attachments would only ever be metadata records with
/// nothing behind them (see DocumentScannerView: OCR text was kept, the scanned image wasn't).
struct AttachmentStore {
    static let shared = AttachmentStore()

    private var directory: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Attachments")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func saveJPEG(_ image: UIImage, filename: String) -> Attachment? {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return nil }
        let id = UUID()
        let url = directory.appending(path: "\(id.uuidString).jpg")
        guard (try? data.write(to: url)) != nil else { return nil }
        return Attachment(id: id, filename: filename, mimeType: "image/jpeg", sizeBytes: data.count, localPath: url.path)
    }

    func delete(_ attachment: Attachment) {
        try? FileManager.default.removeItem(atPath: attachment.localPath)
    }
}
