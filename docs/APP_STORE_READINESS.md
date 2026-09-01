# Life Admin — App Store Submission Checklist

The master checklist. Everything below either points at a doc that's already written, or is a
step only David can do (his Apple ID, his Mac, his App Store Connect account). Nothing here needs
a code change — the app and server are feature-complete for v1.

## Already done (code side)

- [x] Bundle identifier `com.lifeadmin.app`, version 1.0.0 build 1 (`project.yml`).
- [x] Permissions requested only when a feature is actually used, with real usage-description
      strings (`project.yml`).
- [x] No analytics SDK, advertising SDK, tracking SDK, dev endpoint, or committed API key —
      Gemini is only reached through a server-side proxy (`server/gemini-proxy.js`) configured
      with environment secrets.
- [x] 202/202 unit tests passing, 13 locales fully translated and QA-checked
      (`swift test`, `swift run lifeadmin-qa`).
- [x] `scripts/security_scan.sh` passes.
- [x] Camera-based document scanning shipped **disabled** for this first submission
      (`LifeAdminApp/Support/FeatureFlags.swift`) — the feature most likely to draw extra
      review scrutiny in a brand-new app.

## Docs already written for you

| What | Where | What to do with it |
|---|---|---|
| Privacy Policy | `docs/PRIVACY_POLICY.md`, live at https://davidpit1565.github.io/Life-admin/privacy-policy.html | Paste the URL into App Store Connect's Privacy Policy URL field |
| Terms of Use | `docs/TERMS_OF_USE.md`, live at https://davidpit1565.github.io/Life-admin/terms-of-use.html | Optional EULA URL field, or just keep it linked from the app/support page |
| App Privacy questionnaire answers | `docs/APP_PRIVACY_LABELS.md` | Answer key for App Store Connect's "App Privacy" section (Guideline 5.1.1) |
| Listing copy (name, subtitle, description, keywords, category) | `docs/APP_STORE_LISTING.md` | Copy-paste into the corresponding App Store Connect fields |
| Support page | live at https://davidpit1565.github.io/Life-admin/support.html | Paste the URL into App Store Connect's Support URL field |
| How to generate screenshots | `docs/SCREENSHOTS.md` | Run the `ScreenshotTests` UI test, extract PNGs, upload |

## What's left — in order

1. **Install and verify on your own phone first.** `git pull origin main`, `xcodegen generate`,
   open in Xcode, confirm your Team is selected under Signing & Capabilities, connect your
   iPhone, ⌘R. Use the app for real for a bit before submitting anything.
2. **Run the screenshot UI test** (`docs/SCREENSHOTS.md`) against a large Simulator (e.g. iPhone
   17 Pro Max) and pull the PNGs out of the `.xcresult` bundle. This hasn't been run yet —
   verify it works, and adjust `ItemStore.seedDemoDataForScreenshots()` if you want different
   demo data in the shots.
3. **Register the app in App Store Connect** (appstoreconnect.apple.com → My Apps → +) with the
   bundle ID `com.lifeadmin.app`. This has to be you — it's tied to your Apple Developer account.
4. **Fill in the listing** using `docs/APP_STORE_LISTING.md` verbatim, plus the screenshots from
   step 2.
5. **Fill in the App Privacy questionnaire** using `docs/APP_PRIVACY_LABELS.md` as the answer key
   — see the "How to answer" section there for the two identity/tracking questions that apply to
   every row.
6. **Fill in pricing and availability** (this app has no in-app purchases or subscriptions to
   configure — it's a one-time free or paid download, your call).
7. **Archive and upload a build** from Xcode (Product → Archive → Distribute App → App Store
   Connect), then attach that build to the version you just filled in.
8. **Submit for review.**

## Before you submit, worth a final look

- The Privacy Policy and Terms of Use text has not had a professional legal review — both
  documents say so explicitly. That's a judgment call only you can make; get one if you want
  extra certainty for your jurisdiction.
- Decide the app's price tier (or confirm free) and whether you want it available worldwide or
  in specific countries.
- Double-check the contact email (`dp@solfaygroup.com`) and developer name ("David Pit") used
  throughout the legal docs and listing copy still match what you want public.
