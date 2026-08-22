# App Privacy Details — App Store Connect mapping

**Status: draft**, derived directly from the code paths in this repo (see file references below).
This maps to Apple's "App Privacy" questionnaire categories in App Store Connect
(Guideline 5.1.1) — David fills the actual form there using this as the answer key. Re-check this
doc any time the AI extraction path or a permission changes.

## How to answer the questionnaire

For every category below marked **Collected: Yes**, App Store Connect will additionally ask
"Is this data linked to the user's identity?" — answer **No** for all of them, since the app has
no accounts, no device identifiers, and nothing is ever associated with a person across sessions
server-side. It will also ask "Is this data used for tracking?" — answer **No** across the
board; nothing here is used to track users across apps/websites owned by other companies.

| Apple category | Collected? | What, exactly | Why | Where in code |
|---|---|---|---|---|
| **Financial Info** (amounts, currency) | **Yes** | The amount/currency you type for an item — only reaches Gemini/Google when the AI feature sends the item's free text for extraction | Structured extraction of bill/insurance amounts | `Sources/LifeAdminCore/AIService.swift`, `server/gemini-proxy.js` |
| **Contact Info** (name, email) | **Yes** | Only if it happens to appear inside the free text you typed for an item (e.g. "renew with agent@insurer.com") when that text is sent to Gemini. The contact you *link* via the picker (name/company/email) is **not** sent — it never leaves the device. | Same AI extraction path — the model sees whatever text you wrote, in full | `Sources/LifeAdminCore/AIService.swift` (`ProxyAIClient.extract`) |
| **User Content** (the item text itself) | **Yes** | The full text of an item, when the AI feature sends it for extraction | Core feature — natural-language item entry | Same as above |
| **Photos/Videos** | **No** (currently) | Document-scan photos stay on-device only — the OCR text extracted from them can flow into the same AI path as User Content above once you save; the image itself is never uploaded. Feature is shipped **disabled** for the first release (`LifeAdminApp/Support/FeatureFlags.swift`) | — | `LifeAdminApp/Support/DocumentScannerView.swift` |
| **Identifiers** (user ID, device ID) | **No** | No accounts, no advertising ID, no device fingerprinting | — | — |
| **Usage Data** / **Analytics** | **No** | No analytics SDK anywhere in the app | — | (absence confirmed by repo search) |
| **Diagnostics** (crash logs) | **No** | No crash-reporting SDK | — | — |
| **Location** | **No** | Never requested, never read | — | — |
| **Contacts** (as a standing permission) | **No** | The system contact picker hands back one contact locally; the app never requests `CNContactStore` authorization at all | — | `LifeAdminApp/Support/ContactPickerView.swift`, `LifeAdminApp/Views/ItemDetailView.swift` |
| **Calendar/Reminders data** | **No** (stays on-device) | Events/reminders are written to the user's own iOS Calendar/Reminders via EventKit; nothing about them is sent to us | — | `LifeAdminApp/Support/CalendarSyncService.swift` |

## The one line to get exactly right

Apple's guideline (updated Nov 13 2025, see `docs/APP_STORE_READINESS.md`) wants the third party
**named**, not described generically. Wherever App Store Connect lets you specify who data is
shared with, write **"Google (Gemini API)"** — not "a third-party AI service" or similar.

## Also needed in-app (not just in the questionnaire)

The AI-consent screen (`AIConsentView`) already names Gemini/Google explicitly before any data is
sent — this doc is about the App Store Connect form matching that same disclosure, not a
separate thing to build.
