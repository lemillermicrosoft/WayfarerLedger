# Existing-solutions preflight

Checked 2026-09-30 before implementation.

The requested comparison points were **I Remember You** (player-memory/notes) and **GuildMute**-style guild muting. CurseForge pages were blocked by anti-bot protection in this environment, the configured web-search provider was unavailable, and exact GitHub repository searches returned no results. Therefore no source code was downloaded or copied, and no license assumptions were made.

Wayfarer Ledger intentionally differentiates itself through a narrow privacy boundary and unified UX:

- local-only account/per-character memory rather than shared reputation;
- collection only from visible group rosters or an explicit target action;
- notes, markers, search, tooltip recall, export/import, and deletion in one native-feeling interface;
- literal, user-controlled guild patterns with optional local chat assistance, never public allegations;
- secret-value rejection and safe degradation on clients that mark identity data secret.

All implementation in this repository is original and MIT-licensed. A later maintainer should repeat the ecosystem/license check when search access is available before borrowing any external implementation detail.
