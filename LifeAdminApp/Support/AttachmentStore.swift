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

    /// Apple's own documentation for the app's container directory warns the exact path can
    /// change between launches — most concretely, restoring a backup to a new phone gets a new
    /// container UUID even though the SwiftData row (and the file itself) both come along fine.
    /// An `Attachment` saved with today's absolute path would silently point at nothing after
    /// that, showing a generic file icon forever with the real image sitting unreachable on disk.
    /// Resolving the URL fresh from just the filename survives that; `lastPathComponent` also
    /// makes this tolerant of an `Attachment` saved before this fix, which does store the old
    /// full path.
    func url(for attachment: Attachment) -> URL {
        directory.appending(path: (attachment.localPath as NSString).lastPathComponent)
    }

    func exists(_ attachment: Attachment) -> Bool {
        FileManager.default.fileExists(atPath: url(for: attachment).path)
    }

    func saveJPEG(_ image: UIImage, filename: String) -> Attachment? {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return nil }
        let id = UUID()
        let storedFilename = "\(id.uuidString).jpg"
        let url = directory.appending(path: storedFilename)
        guard (try? data.write(to: url)) != nil else { return nil }
        return Attachment(id: id, filename: filename, mimeType: "image/jpeg", sizeBytes: data.count, localPath: storedFilename)
    }

    func delete(_ attachment: Attachment) {
        try? FileManager.default.removeItem(at: url(for: attachment))
    }
}
