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
11. Role-agents: `system-analyst`, `architect`, `teamlead`, `verifier` (сейчас только `code-implementor`).
12. Workflow orchestrator command типа `/feature-request` который автоматически drive state machine end-to-end.
13. `--parallel` mode для orchestrator'а — worktree-per-task execution для roadmap-ready групп (parallel-safe из disjoint blocker sets).
14. JSON output mode для bash helpers (CI / programmatic consumption).
15. Lockfile / advisory locks для concurrent state operations на одной change'е.
16. Optional `yq` для hardened YAML parsing (текущий pure-bash работает но fragile к расхождениям schema).
17. Per-scope skip rules (e.g. `scope: bugfix` → architecture stage default `skipped`).
