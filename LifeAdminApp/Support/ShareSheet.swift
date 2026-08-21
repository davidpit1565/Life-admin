import SwiftUI

/// A thin wrapper around `UIActivityViewController` — SwiftUI has no built-in way to present the
/// system share sheet imperatively (only the declarative `ShareLink`, which needs its item ready
/// before the button even renders). One tap should generate the export file and show the share
/// sheet immediately, not require a second tap once the file happens to exist.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
