# Life Admin

An iOS app for tracking the recurring "life admin" tasks people forget —
renewals, bills, documents, warranties — with natural-language input and an
optional AI assist.

## Structure

- `Sources/LifeAdminCore` — Swift Package with the app's core logic (models,
  natural-language parsing, priority/reminder engines, AI service client).
  Framework-independent, covered by `Tests/LifeAdminCoreTests`.
- `LifeAdminApp` — the SwiftUI app UI. Built via a generated Xcode project
  (see below), not committed directly as an `.xcodeproj`.
- `server/gemini-proxy.js` + `api/extract.js` — a server-side proxy so the
  Gemini API key never ships inside the iOS app. Deployed on Vercel
  (`vercel.json`).
- `tests/` — Node scripts that exercise the Gemini proxy contract.
- `scripts/` — local QA and secret-scanning scripts.
- `docs/` — build/testing setup, Gemini configuration, and App Store
  readiness notes.

## Getting started

```bash
swift test          # run the core package's unit tests
swift run lifeadmin-qa
```

To build the actual iOS app, see [docs/BUILD_AND_TESTING.md](docs/BUILD_AND_TESTING.md)
— it explains how the Xcode project is generated and how CI builds it without
needing a local Mac.

For the Gemini integration, see [docs/GEMINI_CONFIGURATION.md](docs/GEMINI_CONFIGURATION.md).
