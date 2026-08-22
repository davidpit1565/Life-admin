# How we talk about AI and privacy — copy variants

Answers open question #4 from `docs/APP_STORE_READINESS.md`: "Get Adulting" (a direct competitor)
wins trust with "no AI, no cloud" — we do use AI (Gemini) for some items, so copying that line
would be false. These are three honest ways to say what we actually do, for David to pick from
(or merge). Meant for the App Store description / marketing site, not the in-app consent screen,
which already has fixed, code-accurate copy in `AIConsentView` — see `en.lproj/Localizable.strings`
key `aiConsent.body`.

## Variant 1 — Lead with the default

> **Most of what you type, Life Admin understands on your phone — nothing sent anywhere.**
> Only when something's genuinely ambiguous, or it's a big bill or insurance renewal worth a
> second opinion, does it ask Google's Gemini AI for help — and only if you've said yes to that,
> which you can turn off entirely, any time, in Settings.

Best for: App Store description, first line of a privacy-focused landing page. Technically the
most precise (matches `LifeAdminAIService.extract`'s actual confidence-threshold logic), but
"ambiguous" and "second opinion" are a bit abstract for marketing copy.

## Variant 2 — Lead with control

> **You decide if AI ever sees anything.** Life Admin works fully offline with manual entry. Want
> help understanding what you type? Turn on AI processing in Settings, and pick how much: ask
> before every use, run automatically, or off completely.

Best for: onboarding page 3 body copy, or a "Privacy" section on a marketing site. Foregrounds
the three-way `AIProcessingMode` setting that already exists, which is a real, checkable
differentiator against competitors who don't offer a granular AI on/off choice.

## Variant 3 — Lead with the tradeoff, plainly

> **Life Admin can read your bills so you don't have to remember them — using Google's Gemini AI,
> only for the items that need it, only if you agree.** Everything else stays on your phone.

Best for: a single App Store subtitle-length line, or the first sentence of the Privacy Policy
itself (pairs well with the table in `docs/PRIVACY_POLICY.md`). Most direct about naming Gemini
up front, which also happens to be what Apple's current guideline (5.1.2(i)) wants disclosed
early rather than buried.

## What NOT to say

- **"No AI"** or **"100% offline"** — false; some items do reach Gemini when AI is on. This is
  the exact claim that would blow up under App Review scrutiny or a bad-faith competitor
  screenshot.
- **"Your data is safe with us"** with no specifics — means nothing and reads as filler next to
  a competitor (Get Adulting) that's specific about what it doesn't do.
- Anything implying the AI reads *everything* automatically — most items never leave the device;
  overstating AI involvement undersells the actual privacy posture.
