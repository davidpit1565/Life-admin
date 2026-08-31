import SwiftUI
import UniformTypeIdentifiers

/// Wraps `UIDocumentPickerViewController` in "open as copy" mode so a document picked from the
/// Files app — including any cloud provider that plugs into Files as a location, Google Drive or
/// Dropbox among them, if the user has that app installed — lands as a plain local copy this app
/// can read and hand to `AttachmentStore`, without this app ever needing to talk to any of those
/// providers' own APIs or accounts directly.
struct FileImportPicker: UIViewControllerRepresentable {
    var onPicked: (_ url: URL) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.image, .pdf], asCopy: true)
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = true
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (_ url: URL) -> Void
        let onCancel: () -> Void

        init(onPicked: @escaping (_ url: URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }

        // `asCopy: true` above means these URLs already point at temporary copies inside this
        // app's own sandbox — unlike the original document (which could live in another app's
        // container entirely), no security-scoped access request is needed to read them.
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            for url in urls { onPicked(url) }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
