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
        // These files can be photographed IDs, insurance cards, or medical documents — the
        // default protection class stays readable once the device has been unlocked even once
        // since boot, so this matches the app's own opt-in Face ID lock semantics instead:
        // unreadable whenever the device itself is locked.
        guard (try? data.write(to: url, options: .completeFileProtection)) != nil else { return nil }
        // Photographed IDs and insurance cards have no business riding along in an iCloud device
        // backup just because everything else in the app's container does by default — this is
        // guidance to the system rather than a guarantee (Apple's own docs note routine file
        // operations can reset it), so it's a defense-in-depth layer on top of file protection
        // above, never a substitute for it.
        var fileURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? fileURL.setResourceValues(resourceValues)
        return Attachment(id: id, filename: filename, mimeType: "image/jpeg", sizeBytes: data.count, localPath: storedFilename)
    }

    func delete(_ attachment: Attachment) {
        try? FileManager.default.removeItem(at: url(for: attachment))
    }
}
