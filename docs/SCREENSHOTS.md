# App Store Screenshots

A UI test (`LifeAdminUITests/ScreenshotTests.swift`) captures a fixed set of screens against
deterministic demo data, so you don't have to add items by hand every time you need fresh
screenshots. It has not been run yet — verify it once before relying on it.

## Run it

1. Open the project in Xcode (`xcodegen generate` first if you haven't regenerated recently).
2. Pick a Simulator matching the size you need. For the required 6.9" set, use **iPhone 17 Pro
   Max** (or whatever the current largest iPhone Simulator is called).
3. Product → Test (⌘U), or select just the `ScreenshotTests` scheme/test in the Test navigator
   and run that.
4. Repeat with a 5.5"/6.5" Simulator if you want the optional smaller-device screenshots too —
   App Store Connect will otherwise scale the 6.9" set down automatically for older device
   listings, which is usually good enough.

## Get the PNGs out

Xcode saves test screenshots as attachments inside the `.xcresult` bundle, not as loose files. To
pull them out:

1. Find the result bundle: in Xcode, Report Navigator (⌘9) → the test run → right-click → **Show
   in Finder**. It's a `.xcresult` package.
2. In Terminal:
   ```
   xcrun xcresulttool export attachments --path /path/to/Test.xcresult --output-path ~/Desktop/LifeAdminScreenshots
   ```
3. The PNGs land in that output folder, named after the `capture(_:name:)` calls in the test
   (`01-Home.png`, `02-Items.png`, etc.) — upload them directly to App Store Connect.

## What's seeded

`ItemStore.seedDemoDataForScreenshots()` (gated by the `-uiTestScreenshots` launch argument, and
only ever active in this test target) inserts seven items into an in-memory store — an overdue
bill, an upcoming insurance renewal, two subscriptions in the same category (so Insights' overlap
card has something to show), a passport with Document Details fields, a credit card renewal, and
something due today. Real permission prompts and the onboarding/AI-consent screens are skipped
for the same reason: screenshots shouldn't depend on a Simulator's permission state.

Edit that method directly if you want different demo data in the screenshots.
