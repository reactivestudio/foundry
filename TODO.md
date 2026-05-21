# TODO

## Shipped (v0.5.0)

- ~~своя реализация аналог openspec~~ — заменено на 4-bucket + per-stage state-machine модель в `.spec/changes/`. См. README + ARCHITECTURE.md.

## Shipped (v0.5.1)

- ~~Рефакторинг 16 узких bash helpers → 4 dispatch скрипта~~ (`stage-state-machine.sh`, `tracking.sh`, `roadmap.sh`, `change.sh`) с именованными флагами (`--change`, `--stage`, `--state`, и т.д.).

## Shipped (v0.5.2)

- ~~Слить `/backlog-add` + `/backlog-list` → `/backlog`~~ (smart dispatch: bare = list, with title = scaffold).
- ~~Слить `/done-list` + `/declined-list` → `/closed [done|declined]`~~ (опциональный фильтр).
- ~~`/sprint-list` → `/sprint`~~ (короче).
- ~~Дроп `/accept`, `/decline`, `/sprint-add`~~ — accept/sprint-move = auto через `/track`; decline = bash напрямую по natural-language запросу (документировано в `spec-lifecycle`).
- 10 команд → 5 (`/setup`, `/backlog`, `/sprint`, `/closed`, `/track`).

## Shipped (v0.5.4)

- ~~Интерактивный `/backlog`~~ — AskUserQuestion для добавления из пустого, выбора задач для move-to-sprint, переключения на /sprint и /closed inline.

## Shipped (v0.12.0) — /change browse UX: tab-args, no AskUserQuestion, quartile-circle progress, hard-cap title

Four coordinated /change browse-view changes addressing pilot feedback:

- ~~Args replace tab AskUserQuestion~~: tab navigation is now `/change <bucket>` (`all` / `backlog` / `in-progress` / `closed`). The bare `/change` defaults to `All`. Browse view is **read-only** — no modal menu. Drill is `/change <slug>`. Scaffold is `/change "<free text>"`. Arg routing dispatch in Step 0.
- ~~Bucket-priority sort in All tab~~: was sorting by `updated_at` desc globally (mixed buckets), broke the "see what's next in backlog first" mental model. Now: iterate buckets in fixed order (`backlog` → `in-progress` → `done` → `declined`), sort each by `updated_at` desc, concatenate, take top 10. Closed tab uses `done` → `declined` order.
- ~~Title hard-capped at 50 chars~~ (was: 50 padded with overflow up to 150 — broke alignment for rows in that range). Now: any title >50 chars is truncated at 49 + `…`, then right-padded to exactly 50. Alignment holds for every row. Trade-off: long titles get cut visually in list view; drill view still shows the full title.
- ~~Progress format redesigned~~: dropped the parallelogram bar (`▰▰▰▱▱▱▱▱`). New format is `<quartile-circle> [done/total]`. Icon by percentage: `○` (0%), `◔` (≤37%), `◑` (38–62%), `◕` (63–99%), `●` (100%). `0/0` renders as `○ [0/0]` (not `—` — explicit per pilot request).
- Footer hint line replaces the AskUserQuestion at the bottom: `Hint: /change <bucket>  switch tab  ·  /change <name>  drill in  ·  /change "<text>"  scaffold new`.

## Shipped (v0.11.1) — progress bar glyphs: parallelograms

- ~~Progress bar empty glyph `░` → `▱`~~ (WHITE PARALLELOGRAM, U+25B1). Filled glyph correspondingly `█` → `▰` (BLACK PARALLELOGRAM, U+25B0). Both characters are designed as a purpose-built progress-bar pair: equal width, equal visual weight, no shading effect. Example: `▰▰▰▱▱▱▱▱▱▱▱▱  3/12`.

## Shipped (v0.11.0) — relative time + progress bar + title cap 150

- ~~`updated_at` column now relative~~: format `[5 sec ago]` / `[12 min ago]` / `[2 h ago]` / `[7 d ago]` / `[3 mo ago]` / `[1 y ago]`. Computed at list time from the stored `updated_at` timestamp. `change.sh format_relative_time()` helper added.
- ~~New `progress: "done/total"` field in tracking.yaml~~: auto-synced from `roadmap.md` task states. Initial `"0/0"`. Updated by `sync_roadmap_progress` (part of `sync_all`) on every state mutation, and additionally by `roadmap.sh set-task-state` (which now calls `tracking.sh sync` at end).
- ~~Progress bar column~~: rendered from `done/total` as `█` (filled) + `░` (empty) + ` <done>/<total>` label. Bar width capped at 20 chars; for changes with >20 tasks the filled portion scales proportionally. `0/0` or absent → renders as `—`.
- ~~Title cap raised 50 → 150~~ with `…` ellipsis truncation. Title still right-padded to 50 for typical alignment; titles between 50–150 chars expand and locally break alignment of subsequent columns (accepted trade-off).
- TSV cols rearranged: `progress` replaces `roadmap` (col 8); `updated_rel` replaces `updated_pretty` (col 12). 13 cols total, path stays at col 13.

## Shipped (v0.10.1) — column order: title before dates

- ~~Row format reordered~~: `<icon>  <status>  <title>  <created>  <updated>` (was: status + created + updated + title). Title in the middle, dates at the end. Title padded to 50 chars with `…` ellipsis truncation past 49 visible chars. Created padded to 27; updated trailing unpadded.
- ~~Declined `reason:` continuation~~: indent reduced 74 → 16 spaces (aligns under title column).

## Shipped (v0.10.0) — created_at / updated_at + 2 aligned date columns

- ~~`tracking.yaml` schema additions~~: `created_at: "YYYY-MM-DD HH:MM:SS"` (immutable, set once at scaffold time) and `updated_at: "..."` (auto-refreshed on every `tracking.sh` mutation via `sync_all`).
- ~~`tracking.sh sync_all` now includes `sync_updated_at`~~ — called by `set-stage`, `set-scope`, `decline`. Idempotent: re-writes the existing line; if absent (legacy), inserts after `created_at:`. Bug: first draft duplicated the line on each call; fixed by splitting into "replace if exists" vs. "insert if absent" branches.
- ~~`change.sh list` TSV~~: 11 cols → 13 cols. Dropped `last_event_at` / `last_event_pretty`. Added `created_at` (col 9), `created_pretty` (col 10), `updated_at` (col 11), `updated_pretty` (col 12). Path moves to col 13. Fallback: when `created_at`/`updated_at` field absent (pre-0.10.0 yaml), uses last-history-event timestamp.
- ~~/change list rendering~~: row format now `<icon>  <status-11>  <created-27>  <updated-27>  <title>` with status + both dates aligned to fixed widths. Sort order in `All` tab switched from `last_event_at` → `updated_at`.
- ~~Declined-reason continuation line~~: indented to 74 spaces to align under the title column.
- Migration from 0.9.x: no auto-migration. Existing tracking.yaml files without the new fields render via fallback (last history entry) until rebuilt via `/foundry:setup` + `/change`.

## Shipped (v0.9.1) — tabbed /change view + aligned status column + bracketed date

- ~~Tabs replace per-bucket sections~~: `**All [N_all]** · backlog [N_backlog] · in-progress [N_in_progress] · closed [N_closed]` with bold marking the active tab. `closed` = done + declined merged. Default tab on first entry: `All`.
- ~~TAB_LIMIT = 10~~ items per tab (was 3), with `... and <N-10> more in <tab>.` overflow line.
- ~~Tab switching~~: Step 5 action menu now has 4 options — `Switch tab` / `Drill` / `Add new` / `Exit`. Switch tab → nested AskUserQuestion `"Which tab?"` with the 4 tab options.
- ~~Browse form is now a loop~~: each iteration re-fetches counts, re-renders header + list, re-asks action menu. Maintains `CURRENT_TAB` state across iterations.
- ~~Aligned status column~~: each row prints `<icon>  <status_padded_to_11>  <title>  <date>`. Padding 11 = width of longest status (`in-progress`). Date suppressed when fresh-scaffold (no history).
- ~~Date format~~: `[monday, 10:30] [25 feb]` (bracket-wrapped, comma between day and time). Was: `monday [10:30] [25 feb]`. format_pretty_date in change.sh updated.

## Shipped (v0.9.0) — breaking: state machine rewrite (8 states), all-buckets list, pretty dates

- ~~Stage state machine rewritten (8 states)~~: `estimation | required | skipped | pending | in-progress | review | completed | rejected`. Was: `pending | in-progress | need-approve | approved | pause | skipped`. Renames: `need-approve → review`, `approved → completed`. New: `estimation` (initial — decide if stage is needed), `required` (needed but not started), `rejected` (unrealizable, needs upstream rework). `pause` folded into `pending` (semantic shift: blocked, not "deferred").
- ~~Initial state at scaffold = `estimation` for every stage~~ (was `pending`). Tracking template + all docs updated.
- ~~Status derivation rewritten~~: `impl ∈ {estimation, required}` → `backlog`; all of `{impl, verif, term} ∈ {completed, skipped}` → `done`; otherwise `in-progress`. `pending`/`rejected` keep status `in-progress`.
- ~~Stage derivation rewritten~~: first stage whose state ≠ `{completed, skipped}`. Fresh-scaffold change has `stage: refinement` (not `none`).
- ~~/change no-arg view rewritten~~: dropped the bucket picker. Now always lists ALL 4 buckets in fixed order (backlog → in-progress → done → declined), top 3 per bucket with `+ N more.` overflow. Per-bucket sections, header line, blank line between.
- ~~Action menu in drill view rewritten~~ to use new state names (`Start (in-progress)` / `Send to review` / `Approve (completed)` / `Reject` / `Mark required` / `Mark blocked (pending)` / etc.). Context-aware per stage-state.
- ~~Pretty date format~~: `change.sh list` TSV now emits 11 columns — added `last_event_pretty` (col 10) formatted as `monday [10:30] [25 feb]` (full lowercase day, abbreviated month). BSD `date -j -f` primary, GNU `date -d` fallback.
- ~~Skills+agent updated~~: spec-conventions, spec-lifecycle, spec-refinement, system-analyst (state-name refs); README + ARCHITECTURE.md.
- No auto-migration from 0.8.x — state-name renames are incompatible with existing tracking.yaml files; rebuild .spec/ from /foundry:setup or hand-edit.

## Shipped (v0.8.1) — list rendering: icon-prefixed plain list

- ~~/change Step 2: drop markdown table~~. Replace with one-line-per-item plain list, prefixed by status icon: `○` backlog, `●` in-progress, `✓` done, `⊗` declined. Format: `<icon> <title> — <last_event_at>`. Multi-bucket view (closed = done+declined) prints per-bucket sections with single-word headers. For declined rows, second indented line shows `reason: <decline_reason>`. Fresh-scaffold items (no history) omit the ` — <date>` suffix.
- ~~/change Step 5 drill view~~: prepend status icon to the change header.

## Shipped (v0.8.0) — Phase A: refinement stage (system-analyst agent)

- ~~Agent `system-analyst` (opus)~~: refines a change → reads propose.md + .spec/standards/*.md → runs clarifying-questions loop → sets scope → writes requirements.md → marks refinement need-approve. Preloads spec-refinement + clarifying-questions + spec-conventions + spec-lifecycle.
- ~~Skill `spec-refinement`~~: FR/NFR taxonomy, scope categorisation (product/project/feature/bugfix), requirements.md schema, when-to-ask-vs-defer rules, anti-patterns.
- ~~Template `.template/requirements.md`~~: scaffold with all canonical sections (Context, Problem, Scope In/Out, FR, NFR, Constraints, Open questions, Acceptance criteria).
- ~~/setup updated~~: now scaffolds 4 template files (added requirements.md).
- ~~/change wire-up~~: "Start refinement" action (in both Step 5 drill menu and Step 10 post-scaffold prompt) now invokes the system-analyst agent via Task tool. User clicks "Start refinement" → agent does the work → returns structured "Refinement draft" report → user reviews → drill → Approve.
- /change `allowed-tools` extended with `Task`.

## Shipped (v0.7.3) — template hygiene

- ~~`{{description_indented}}` → `{{description}}`~~ — короче, и в самом template placeholder теперь правильно отступлен (2 spaces под `description: |`), так что raw template — валидный YAML.
- ~~propose.md template минимально структурирован~~: 3 секции (`## Intent`, `## Context`, `## Notes`) с HTML-комментариями-плейсхолдерами. /change теперь подставляет TASK_TEXT в `## Intent`, оставляя `## Context` / `## Notes` для пользователя / system-analyst.

## Shipped (v0.7.2) — /setup: mandatory ask + always-run idempotent scaffold

- ~~Pilot bug v2: even with Read-probe, /setup silently skipped .spec/ scaffolding entirely~~. Root cause: ANY conditional probe (test -d OR Read-marker) gave Claude a place to short-circuit to a "skip silently" branch when context was ambiguous. Fix: drop the probe ENTIRELY. Step 4 now ALWAYS asks "Set up .spec/?". On Yes → ALWAYS runs the scaffold loop (mkdir + per-file Read+Write — existing files never overwritten). No more "if X then skip" branches. Re-asking is cheap because the loop is idempotent.
- Aligned all setup.md sections (What gets installed / Hard rules / Important) with the new always-ask flow.

## Shipped (v0.7.1) — /setup probe via Read instead of `test -d`

- ~~Pilot bug: `/foundry:setup` reported `.spec` already exists and skipped copy~~ when `.spec/` was actually absent. Root cause: `Bash test -d` probe + Claude's exit-code interpretation was fragile (literal `R/.spec` if `R` not expanded → relative path; or exit 1 misread as "command failed = exists"). Fix: drop all `test -d` probes; use `Read` of a canonical marker file (`.spec/changes/.template/tracking.yaml`) — file-not-found is unambiguous. Dropped `cp -r` in favour of 3× `Read`+`Write` (only 3 template files). Removed legacy-detection (sunk cost — nobody migrating from 0.4.x anymore).

## Shipped (v0.7.0) — folded commands + flat YAML + termination stage

- ~~Drop commands `/in-progress`, `/closed`, `/track`~~ — folded into `/change` interactive flow (bucket picker → table → drill → context-aware action menu).
- ~~Drop skill `spec-workflow`~~ — content moved into `spec-lifecycle` (stage → artifact → role mapping table). 5 skills → 4.
- ~~Add 6th stage `termination`~~ — post-verification work (docs, announce, deploy confirm). Status derivation now considers all three of `{implementation, verification, termination}`.
- ~~Flat YAML schema~~: drop nested `stages:` block; each stage = top-level key. Add `stage:` field (derived, mirrors current active stage).
- ~~Explicit `stage:` field~~ — derived by `tracking.sh derive-stage`, synced alongside `status:` via `tracking.sh sync` (alias kept: `sync-status`).
- ~~`tracking.sh` API additions~~: `derive-stage`, `sync` (replaces `sync-status`; alias preserved); `active-stage` subcommand removed (covered by `derive-stage`).

## Shipped (v0.6.1) — refinement of 0.6.0

- ~~Template dir `_template/` → `.template/`~~ (hidden-file convention).
- ~~`description:` multi-line up to ~500 chars~~ via YAML `|`-literal block. Title up to ~120 chars.
- ~~Drop ALL `lifecycle` history entries~~ — `created`, `moved-to-*`, `declined`, `scope-set:*` dropped. History now contains ONLY real stage transitions. Decline audit lives in `decline_reason:` field; scope lives in `scope:` field.
- `change.sh new` substitution moved from sed to awk + ENVIRON (multi-line aware).

## Shipped (v0.6.0) — breaking

- ~~Schema rewrite~~: `id` (= slug), `title`, **`description`** (LLM-generated), **`status`** (derived: backlog \| in-progress \| done \| declined), `scope`, `stages`, `history`.
- ~~Stage rename~~: `analysis`→`refinement`, `architecture`→`design`. Остальные без изменений.
- ~~Bucket rename~~: `sprint/`→`in-progress/`. Backlog/done/declined без изменений.
- ~~File rename~~: `proposal.md`→`propose.md`.
- ~~Команда `/backlog` → `/change`~~. Команда `/sprint` → `/in-progress`.
- ~~LLM-generated slug (3-4 segments)~~ + LLM-generated description — генерируются на этапе `/change` из текста задачи.
- ~~History format~~: seconds precision (`YYYY-MM-DD HH:MM:SS`), pseudo-stage `_meta` → `lifecycle`.
- Migration legacy `.spec/` (0.5.x → 0.6.0) — out of scope, follow-up как `/migrate`.

## Active

1. Добавить возможность выбирать стэк проекта и подгружать только нужные скиллы, команды, агенты, хуки.
2. Добавить анализ кодовой базы → архитектурные проблемы, алгоритмические, перформанс, метрики кода.
3. Добавить авто-создание спецификаций проекта → stack, парадигмы, архитектура, best/bad practices, code style, соглашения (заполнение `.spec/standards/*.md` сейчас руками).
4. Команды должны называться глаголами: `review`, `design`, `implement`, … универсальные команды. Описывают последовательность действий, спеки для учёта, агентов и workflow (orchestrator → agent → loop), скиллы.
5. Агенты по ролям: `reviewer`, `code-implementor`, `architect`, … понимают свои скиллы из спецификаций и docs проекта. Описывают как применять знания.
6. Скиллы — существительные: `adr`, `solid`, `clean-code`, … описывают знания.
7. Конфликты скиллов → интерактивный выбор: первый / второй / никакой / компромисс / другое.
8. `skill` команда — создание скилла (поиск по книгам, opensource проектам, best-practices), тестирование на промтах + анализ эффективности.
9. Агент и скилл `feature-decomposition`.

## v0.5.0 follow-ups (specific to .spec/ subsystem)

10. `/migrate` command для legacy `.spec/specs/` + `changes/archive/` + `project.md` + `config.yaml` → новая 4-bucket структура.
11. Role-agents: `architect`, `teamlead`, `verifier`, `terminator` (есть: `code-implementor`, `system-analyst`).
12. Workflow orchestrator command типа `/feature-request` который автоматически drive state machine end-to-end.
13. `--parallel` mode для orchestrator'а — worktree-per-task execution для roadmap-ready групп (parallel-safe из disjoint blocker sets).
14. JSON output mode для bash helpers (CI / programmatic consumption).
15. Lockfile / advisory locks для concurrent state operations на одной change'е.
16. Optional `yq` для hardened YAML parsing (текущий pure-bash работает но fragile к расхождениям schema).
17. Per-scope skip rules (e.g. `scope: bugfix` → architecture stage default `skipped`).
