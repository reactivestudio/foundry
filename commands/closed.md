---
name: closed
description: "List closed changes — done/ and declined/. Bare = both; pass 'done' or 'declined' to filter."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh:*) Bash(grep:*) Read
---

List changes in the two terminal buckets — `done/` (successfully completed) and `declined/` (rejected). One unified view; filterable.

Arguments:
- `/closed` → both buckets.
- `/closed done` → only `done/`.
- `/closed declined` → only `declined/`.

Read-only.

## Procedure

1. **Determine filter.** From `$ARGUMENTS`:
   - empty → `BUCKETS="done declined"`
   - `done` → `BUCKETS="done"`
   - `declined` → `BUCKETS="declined"`
   - anything else → reject with `usage: /closed [done|declined]`.

2. **For each requested bucket** run `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list --bucket <bucket>`. Collect the TSV rows.

3. **Render.** Group output by bucket. For each non-empty group, render a markdown table.

   **`done/` table** — columns: `Name | Title | Scope | Roadmap | Completed at`.
   ```
   ### done/
   | Name | Title | Scope | Roadmap | Completed at |
   |---|---|---|---|---|
   | add-2fa-totp | Add 2FA via TOTP | feature | 5/5 done · Q1 done | 2026-05-20 19:00:42 |
   ```

   **`declined/` table** — columns: `Name | Title | Reason | Declined at`. For each row, augment with the `decline_reason` field: `Bash`: `grep '^decline_reason:' <path>/tracking.yaml` and strip the `decline_reason: ` prefix + surrounding quotes. If missing → render `—` and add a warning footer.
   ```
   ### declined/
   | Name | Title | Reason | Declined at |
   |---|---|---|---|
   | add-sms-fallback | SMS fallback for 2FA | superseded by add-totp | 2026-05-21 10:00:00 |
   ```

4. **Report counts** per bucket at the end:
   ```
   12 changes in done/
   2 changes in declined/
   ```

   For empty buckets: `done/ is empty.` / `declined/ is empty.`

## Important

- Strictly read-only.
- Closed changes are kept indefinitely as history. Names from `done/` and `declined/` occupy the slot — `change.sh validate-name` will refuse re-using them.
- For a single change's full audit trail, use `/track <name>` (reads `tracking.yaml` history).
- To decline an active change, ask in natural language ("decline X because Y") — agent invokes `tracking.sh decline` + `change.sh move --to declined` directly per `spec-lifecycle`.
