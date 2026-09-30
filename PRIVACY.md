# Privacy and safety model

Wayfarer Ledger is a private notebook, not a reputation service.

## Data it stores

Only data needed for local recall is stored in WoW SavedVariables:

- character name and realm;
- guild name when the client exposes it for a visible unit;
- encounter time, party/raid/manual-target context, and bounded recent group timeline;
- notes, tags, and a personal positive/neutral/caution marker entered by the player;
- local settings and up to three user-initiated safety backups.

Encounter history is capped at 40 entries per player. Group history is capped at 100 sessions per scope. Import accepts at most 1 MiB and 5,000 player records.

## Data it does not store or send

- no chat message or chat body;
- no Battle.net, real-world, device, or account identity data;
- no public scores, reports, accusations, or shared blocklists;
- no network messages, addon communications, analytics, or telemetry;
- no automated targeting or player interaction.

The optional chat filter receives a client callback but deliberately ignores message text. It can locally hide a message only when its non-secret author is already in the ledger and that record's guild matches a user-entered literal fragment.

## Secret values on Interface 16001

Potential API values are checked with `issecretvalue` before their type or content is inspected. Secret, malformed, or unavailable values are rejected. The addon does not stringify, compare, persist, display, export, or branch on secret payloads. Group/target capture fails closed when unit identity is unavailable.

## Export, backup, deletion

Export text remains in the addon's edit box until the player copies it. Import is parsed and validated into staging tables before any ledger record changes. A local backup is required before import or reset. **Forget** removes one player from the selected scope after confirmation. **Reset scope** clears that scope after confirmation and backup. SavedVariables and copied exports remain the player's responsibility.
