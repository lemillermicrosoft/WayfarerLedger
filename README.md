# Wayfarer Ledger

A privacy-first, local social-memory notebook for WoW Forever (`Interface 16001`).

## Alpha features

- Remembers visible party/raid members and players you explicitly add from your current target.
- Account-wide or per-character ledgers, selected in the main window.
- Private notes, tags, positive/neutral/caution markers, guild, last-seen time/context, encounter count, and search.
- Quiet “met before” player tooltips and an optional once-per-session target notice.
- User-owned literal guild-name patterns. Matches are shown locally; optional chat hiding only applies to known ledger players. No public accusation or automatic targeting.
- Plain-text export/import plus per-player forget controls.
- Defensive handling of secret values via `issecretvalue` when the client provides it; unsafe values are ignored.

## Privacy boundary

All data is stored in WoW SavedVariables on the local computer. Wayfarer Ledger does **not** create public reputation scores, transmit notes, share accusations, store chat content, automate targeting, or collect real-world information. Export data leaves the addon only when the user copies it.

## Install

Copy the `WayfarerLedger` directory to:

`World of Warcraft/_forever_/Interface/AddOns/WayfarerLedger/`

Restart WoW or reload the UI. Open with `/wl`, `/wayfarer`, or Esc → Options → Wayfarer Ledger. Use `/wl add` or **Add target** to manually remember a targeted player. Use `/wl reset` or the Options button to reset the ledger window position.

## SavedVariables

- `WayfarerLedgerDB` — account ledger and settings
- `WayfarerLedgerCharDB` — current-character ledger

## Status

`0.1.0-alpha`: installable and statically validated, but requires in-client testing on WoW Forever. Distribution ZIPs are built into `dist/`.
