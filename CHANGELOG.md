# Changelog

## 0.2.0-rc.1 — 2026-09-30

- Completed the privacy-first MVP candidate without publishing a release.
- Added bounded per-player encounter history and recent party/raid session timelines with context.
- Added canonical case-insensitive name/realm keys, safe schema migration, and duplicate merging.
- Added searchable marker filters and deterministic recent/name/met-count sorting.
- Added confirmed account/character copy and move workflows with merge behavior.
- Upgraded export/import to v2 with encounter rows, strict escaping and bounds, full staging before writes, compatibility with v1, and mandatory pre-import backups.
- Added three-slot local safety backups plus confirmed restore and scope-reset flows.
- Split party and raid capture controls and made tooltip note display separately opt-in.
- Expanded onboarding, recent-group empty state, restrained notifications, and literal guild-pattern assistance.
- Hardened Interface 16001 secret-value handling and documented privacy invariants; chat bodies remain ignored and unpersisted.
- Added deterministic codec fuzz/model checks, package validation, privacy docs, and an in-client smoke-test checklist.

## 0.1.0-alpha — 2026-09-30

- Initial installable alpha with local account and character ledgers, group/target capture, notes/tags/markers, search, tooltip recall, options, guild-pattern assistance, export/import, and forget controls.
- Added Blizzard/native (default) and Bronze/custom appearance options.
