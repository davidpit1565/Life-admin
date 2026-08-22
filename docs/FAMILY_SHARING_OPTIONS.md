# Family/shared use — feasibility spike (no decision made here)

**Purpose:** answer "what would it actually take," not "should we." The open question from
`docs/APP_STORE_READINESS.md` (single-user vs. family/shared) is David's call — this just maps
the real options so that decision isn't made blind.

## Where the app is today

`LifeAdminApp.swift` creates a plain local `ModelContainer(for: PersistedItem.self)` — SwiftData,
on-device only, no CloudKit container configured at all. Every item, attachment, and setting is
private to the one device it was created on (a JSON export/import is the only way data moves
between devices right now). Sharing anything today means literally nothing changes automatically
— there's no existing sync layer to extend, this would be new infrastructure either way.

## Option A — SwiftData + CloudKit private sync only (no sharing)

Add a `ModelConfiguration(cloudKitDatabase: .private("iCloud.<bundle-id>"))` so a *single* user's
own items sync across their own devices via their personal iCloud account.

- Solves "I switched phones" and "I use an iPad too," not "my spouse should see this."
- Requires: enabling the iCloud + CloudKit capability in the Apple Developer account
  (David-owned step, needs the paid membership), a `SchemaVersion`/migration plan since SwiftData
  has real constraints under CloudKit (every attribute needs a default value or must be optional;
  no unique constraints), and testing across two of the same person's real devices.
- Smallest step available. Doesn't touch the "single vs. family" question at all — worth doing
  either way once there's an Apple Developer account, independent of that decision.

## Option B — SwiftData + CloudKit *shared* database (real family sharing)

`ModelConfiguration(cloudKitDatabase: .private(...))` plus `CKShare` for specific records, using
`UICloudSharingController` for the actual "invite a family member" UI. This is what lets a second
person (with their own Apple ID) see and edit some or all items.

- Real design decisions this forces, not just engineering ones:
  - **Whole household or per-item?** CloudKit shares at the *zone* level cleanly, not per-record
    easily — sharing "some items but not others" with one person is the hard case, sharing
    "everything" is the easy case. PAM and KinSync (the direct competitors) both went with
    household-wide sharing for this reason.
  - **Who can delete/edit what?** CloudKit gives you participant permissions (read-only vs.
    read-write) but nothing more granular out of the box — "my partner can see the insurance
    renewal but not edit it" needs custom logic on top.
  - **Attachments** (scanned documents) live as local files today, referenced by path — those
    need to become `CKAsset`s to be shareable at all, which is its own migration.
  - **The AI-consent and autonomy-mode settings are per-device UserDefaults today** — a shared
    household raises the question of whose settings govern a shared item's AI processing.
- Rough size: this is a multi-week rebuild of the storage layer, not a feature added on top of
  the current one. Realistic to scope only after the app has shipped and has real single-user
  usage data to justify the investment.

## Option C — Lighter-weight: "share a read-only snapshot," not live sync

Reuse the JSON export that already exists (Settings → Export) — generate a snapshot on demand
and hand it to someone else (AirDrop, Files, Mail) rather than building live multi-device sync.
No new infrastructure at all; it's the existing export feature used for a slightly different
purpose. Doesn't give real-time shared state (if they edit something, it doesn't come back), but
answers "let my accountant see everything at tax time" or "hand my adult child a copy before a
trip" without months of work.

## What this doesn't answer

Whether family use is worth building at all is a product/positioning call (open question #3 in
`docs/APP_STORE_READINESS.md`), not an engineering one — this doc exists so that call can be made
knowing the real cost of each option, not a guess at it.
