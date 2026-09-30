# Candidate smoke test — 0.2.0-rc.1

Use a clean or backed-up `_classic_beta_` profile with **Script Errors** enabled. Do not test with irreplaceable SavedVariables.

1. Install the ZIP as `Interface/AddOns/WayfarerLedger`, log in, and confirm `/wl` opens without Lua errors.
2. Confirm the first-run empty state explains local storage and shows no fake players.
3. Target another visible player. Choose **Add target**; verify name, realm, guild (when available), context, and one target encounter. Verify self/NPC/no target is rejected.
4. Join and leave a party, then a raid. Verify each visible member is captured once per encounter burst; roster churn does not rapidly inflate counts; recent sessions appear in the empty-state timeline.
5. Meet a saved player again. Verify the tooltip shows marker, last seen, context, and tags. Enable target notification and verify it prints once per session. Private note text must remain hidden until its separate option is enabled.
6. Add a note, tags, and each marker. Reload UI and verify persistence. Search every field, cycle all marker filters, and test Recent/Name/Met count sorting.
7. Copy and move a player between Account and Character. Verify destination duplicates merge and a move removes only the source copy.
8. Add mixed-case duplicate names (through import fixture if needed) and confirm they normalize to one realm-qualified record.
9. Enter a guild pattern containing Lua pattern characters such as `[]%.`. Verify matching is literal and case-insensitive. Enable local chat hiding and confirm only known matching authors are hidden; no message body appears in SavedVariables.
10. Export, edit nothing, and import. Verify a backup is created and encounter history survives. Reject empty, wrong-header, overlong, invalid-escape, out-of-order-event, over-1-MiB, and over-5,000-record payloads without partial changes.
11. Create a manual backup. Change data, then restore latest and verify merge behavior.
12. Confirm **Forget**, **Move scope**, **Reset scope**, and **Restore latest** each require confirmation. Cancel each once. Reset a test scope, then restore it.
13. Switch Blizzard/native and Bronze/custom appearance live. Move the window, reload, reset its position, and verify scale-safe placement.
14. Inspect `WTF/Account/.../SavedVariables/WayfarerLedger.lua`: no chat bodies, secrets, public scores, network queues, or unbounded history.
15. Log out during a party and log back in. Confirm the previous session closes safely and no errors occur.

Release remains intentionally on hold until this checklist passes in client.
