---
title: Privacy Policy — Life Admin
layout: default
---

# Privacy Policy — Life Admin

_Written directly from the app's actual code so every claim below is checkable against a specific
file. This has not had a professional legal review — if you need one for your jurisdiction, get
one before relying on this as your sole compliance document._

_Last effective: September 1, 2026_

## The short version

Life Admin stores what you enter on your device. It never has user accounts, never runs
analytics or advertising SDKs, and never sells or shares your data with anyone for marketing.
The only thing that ever leaves your device is the text of an item you're adding — and only when
all of the following are true: you turned AI on, and either the on-device parser couldn't
confidently understand what you typed, or the item looks like a large bill or insurance renewal
that's worth a second opinion. That text goes to Google's Gemini API through our own proxy
server, purely to extract a title/amount/date/category — nothing is stored there afterward.

## What's stored, and where

| Data | Where it lives | Leaves your device? |
|---|---|---|
| Items you add (title, amount, currency, due date, category, notes) | On-device, in the app's local database (SwiftData) | Only the raw text, and only per the AI rule above |
| Photos/scans of documents you choose to attach | On-device, in the app's local file storage | No |
| A contact you link to an item (name, company, email) | On-device, copied from the one contact you pick in the system picker | No |
| Calendar events / reminders you create from an item | Your iOS Calendar/Reminders, via Apple's EventKit | No — stays inside Apple's frameworks, on your device and whatever calendar accounts *you* configured in iOS Settings (which may include your own iCloud or Google account — that sync is between you and Apple/Google, not something this app sends anywhere) |
| Notification content | iOS's local notification system | No |
| A backup you export | A JSON file you choose where to save/share | Only if and where you send it yourself |

Deleting the app deletes everything in the first four rows. There is no server-side copy to
separately request deletion of.

## The AI feature, specifically

When enabled, item text you type or scan is sent to a small proxy server we run, which forwards
it to Google's Gemini API (model configured in `server/gemini-proxy.js`) with a fixed instruction
to extract structured fields (title, category, amount, currency, date, recurrence, reminders) and
nothing else. The proxy does not log or store the text itself; on error it logs only the HTTP
status and a truncated error body, with any key/token fields stripped (see `safeLog` in
`server/gemini-proxy.js`).

- Turned off in Settings → nothing is ever sent, regardless of how confident the on-device parser
  is.
- Turned on, but you declined (or haven't yet answered) the AI-consent screen shown on first
  launch → same as off. This is enforced in code (`ItemStore.autonomyMode`), not just in the UI.
- Turned on and consented → most items are still handled entirely on-device; Gemini is only
  consulted when the local parser is unsure, or for higher-stakes categories (insurance, bills,
  money) above a size threshold.

Our Gemini API key is on Google's paid tier, which means Google does not use these prompts or
responses to train its models. Google retains request logs for up to 55 days solely to detect
abuse, then deletes them automatically. See
[Google's Gemini API data logging policy](https://ai.google.dev/gemini-api/docs/logs-policy) for
details, which may change — this section reflects that policy as of the date above.

## What we don't do

- No account creation, no login, no device identifiers tied to a person.
- No analytics or crash-reporting SDKs.
- No advertising or ad-attribution SDKs.
- No selling or sharing of your data for any third party's marketing.

## Permissions

The app only asks for a permission at the point it's actually needed for a feature you're using,
and every feature keeps working (with manual entry) if you say no:

- **Notifications** — to remind you before something's due.
- **Calendar / Reminders** — to add an event/reminder for an item, only when you have a due date.
- **Camera** — to scan a document. *(Currently shipped disabled — see `FeatureFlags.swift`.)*
- **Contacts** — never requested as a standing permission. Linking a contact opens the system's
  own contact picker, which hands the app only the one contact you pick and requires no
  permission grant at all.

## Children

Life Admin is not directed at children and does not knowingly collect data from children.

## Changes to this policy

If what the app collects or sends changes, this document changes with it, and the effective date
above will be updated.

## Contact

Questions about this policy: dp@solfaygroup.com.
