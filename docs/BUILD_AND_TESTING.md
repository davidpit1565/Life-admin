# Build & Testing Setup

## Why there was no Xcode project before

This repo started as a Swift Package (`Package.swift` + `Sources/LifeAdminCore`)
with an app UI (`LifeAdminApp/`) that was never wired into any build system —
there was no `.xcodeproj`, no `Info.plist`, and no CI. Nothing could actually
be built into an installable iOS app.

## What changed

The `.xcodeproj` is now **generated, not committed**. The source of truth is
`project.yml` at the repo root, read by [XcodeGen](https://github.com/yonaskolb/XcodeGen).
This avoids hand-editing a fragile, binary-ish `project.pbxproj` file and keeps
the whole project definition reviewable as plain text in pull requests.

To generate the actual `.xcodeproj` (only possible on a Mac with Xcode and
Homebrew installed):

```bash
brew install xcodegen
xcodegen generate
open LifeAdmin.xcodeproj
```

## Continuous Integration

`.github/workflows/ios-ci.yml` runs on every push/PR using a GitHub-hosted
macOS runner — **no local Mac or Apple Developer account required** to get a
build/test signal:

1. `swift test` — runs the full `LifeAdminCoreTests` suite.
2. `scripts/security_scan.sh` — fails the build if a secret or placeholder
   string leaks into the repo.
3. `xcodegen generate` — regenerates `LifeAdmin.xcodeproj` from `project.yml`.
4. `xcodebuild build` for the iOS Simulator with `CODE_SIGNING_ALLOWED=NO` —
   proves the actual app target compiles, without needing any signing
   certificate or paid developer account.

## What's still needed for on-device testing (TestFlight)

Simulator builds prove the code compiles, but running on a real iPhone (via
TestFlight) needs code signing, which needs an **Apple Developer Program**
membership (paid, $99/year — https://developer.apple.com/programs/enroll/).

Once that's in place, the CI workflow can be extended with:
- An App Store Connect API key (stored as a GitHub Actions secret)
- Fastlane `match` (or manual signing certificates/profiles)
- A `fastlane` lane that archives the app and uploads the build to
  TestFlight automatically on pushes to a release branch

This is intentionally not set up yet, since it requires the developer account
to exist first. Nothing above blocks that from being added later without
restructuring what's already here.

## Running things locally right now (no Mac needed)

- `swift test` — not runnable in a plain Linux/CI shell without a Swift
  toolchain for Apple platforms; this only works on macOS or in the GitHub
  Actions workflow above.
- `node tests/gemini-model-contract.js` — verifies the Gemini proxy's
  model/endpoint contract, works anywhere Node.js runs.
- `node tests/gemini-integration.js` — exercises the real Gemini proxy; set
  `GEMINI_API_KEY` (calls `callGemini` directly) or `LIFE_ADMIN_PROXY_URL`
  (calls a deployed `/v1/extract` endpoint).
- `./scripts/security_scan.sh` — secret/placeholder scan, works anywhere
  `ripgrep` (`rg`) is installed.
