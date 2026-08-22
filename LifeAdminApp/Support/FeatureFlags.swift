/// Compile-time switches for features that are fully built but deliberately held back from the
/// first App Store submission — Apple's review scrutinizes camera+AI data flows most closely in
/// a brand-new app with no usage history yet. Flip a flag to `true` and rebuild once there's a
/// track record to point to; nothing else about the feature needs to change.
enum FeatureFlags {
    /// VisionKit document scanning + on-device OCR feeding straight into the AI extraction
    /// pipeline (`DocumentScannerView`, wired into `AddItemView`) — the single feature most
    /// likely to draw extra review scrutiny in a first submission.
    static let documentScanningEnabled = false
}
