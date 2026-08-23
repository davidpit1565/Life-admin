/// Compile-time switches for features that are fully built but deliberately held back from the
/// first App Store submission — Apple's review scrutinizes camera+AI data flows most closely in
/// a brand-new app with no usage history yet. Flip a flag to `true` and rebuild once there's a
/// track record to point to; nothing else about the feature needs to change.
enum FeatureFlags {
    /// VisionKit document scanning + on-device OCR feeding straight into the AI extraction
    /// pipeline (`DocumentScannerView`, wired into `AddItemView`) — the single feature most
    /// likely to draw extra review scrutiny in a first submission.
    static let documentScanningEnabled = false

    /// Mark Done / Snooze buttons on a reminder notification (`NotificationActionHandler`).
    /// Off means a plain banner with no extra buttons — still fully functional, just less for a
    /// first review to look at.
    static let notificationActionButtonsEnabled = false

    /// The once-a-day "here's what needs you" summary notification
    /// (`NotificationScheduler.scheduleDailyDigest`) — background-scheduled, content built from
    /// item data rather than a fixed string, which reads as more autonomous behavior to review.
    static let dailyDigestEnabled = false

    /// Detecting "I'm moving" language in an item's text and surfacing the Home banner
    /// (`LifeEventDetector`, `HomeView.hasMovingEvent`).
    static let moveDetectionEnabled = false

    /// Silently carrying a contact forward onto a new item with the same title as a past one
    /// (`ItemStore.add`'s `priorMatch` lookup) — exactly the kind of unasked-for automatic
    /// behavior a first review scrutinizes most.
    static let contactContinuityAutoFillEnabled = false
}
