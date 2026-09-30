# Wayfarer Ledger

A privacy-first, local social-memory notebook for WoW Forever (`Interface 16001`).

## MVP candidate features

- Quietly remembers visible party/raid members and players explicitly added from the current target.
- Keeps bounded per-player encounter history plus a recent party/raid timeline and context.
- Account-wide and per-character ledgers with confirmed copy/move workflows and duplicate-safe merges.
- Private notes, tags, positive/neutral/caution markers, guild, last-seen context, encounter count, and literal search.
- Sort by recent encounter, name, or met count; filter by personal marker.
- Restrained “met before” tooltips and an optional once-per-session target notice. Note text in tooltips is separately opt-in.
- User-owned, literal, case-insensitive guild fragments. Optional local chat hiding only applies to known ledger players; chat bodies are never read by addon logic or persisted.
- Transactional, bounded plain-text import/export with canonical name/realm normalization and duplicate merging.
- Confirmed per-player forget, scope reset, safety backup, and restore flows.
- Blizzard/native default appearance or optional Bronze/custom styling, applied live.
- Accessible empty-state onboarding with real recent-group context and no fake records.

## Privacy boundary

Everything stays in WoW SavedVariables on this computer unless the player copies an export. Wayfarer Ledger has no network sharing or telemetry and does **not** store chat content, publish scores, share accusations, automate targeting, or collect real-world information. Potential secret values are rejected before inspection or storage. See [PRIVACY.md](PRIVACY.md).

## Install

Copy the `WayfarerLedger` directory to the appropriate WoW client:

`World of Warcraft/_classic_beta_/Interface/AddOns/WayfarerLedger/`

For a WoW Forever install, the client directory may instead be `_forever_`. Restart WoW or reload the UI. Open with `/wl`, `/wayfarer`, or Esc → Options → Wayfarer Ledger.

- `/wl add` — explicitly remember the current player target
- `/wl options` — open options
- `/wl reset` — reset only the ledger window position

## Storage and limits

- `WayfarerLedgerDB` — account ledger, settings, and up to three local safety backups
- `WayfarerLedgerCharDB` — current-character ledger and timeline
- 5,000 imported player records, 1 MiB import text, 40 encounters per player, 100 group sessions per scope

## Candidate status

`0.2.0-rc.1` is packaged and statically/data-model validated. It is **not released** pending the in-client checklist in [TESTING.md](TESTING.md). Candidate ZIPs are built into `dist/`.
