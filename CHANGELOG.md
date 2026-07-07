# Changelog

Формат: одна запись на осмысленную серию версий; полная гранулярность —
в `git log` (каждый коммит несёт версию и расшифровку).

## 0.33.27 — 2026-07-07

- README: usage-секция CLI, установка, гарантии, разработка; CHANGELOG.
- `skills/spec/lifecycle`: LLM-контракт state machine дополнен
  `transitions-from`.

## 0.33.25–0.33.26 — 2026-07-07

- Прочность: TUI переживает отказы state machine (subshell-изоляция);
  санитизация `\n`/`\t` на всех точках записи tracking/history.
- Тесты: 100 проверок в 4 сьютах (smoke/picker/store/pages), CI на
  ubuntu+macos (macos = bash 3.2), pre-commit hook.
- `foundry version`; `list --bucket` валидируется; реестр бакетов
  (порядок+иконка+цвет+валидность) в `config/constants.sh`.
- Портабельность bash 5.x: `shopt -u patsub_replacement`
  (sed-семантика `&` в `${var//…}` ломала render_template), `${#2}`
  под `set -u`; совместимость shellcheck 0.10/0.11.

## 0.33.21–0.33.24 — 2026-07-06…07

- CLI-монолит `app` (2200 строк) разобран на слои:
  `config/spec/store/render/commands/pages`, app = bootstrap+dispatch.
- `spec/` = правила CRISPY (зеркалит `skills/spec/`), `store/` = данные;
  зависимости: pages → commands → render → store → spec → config.
- Нейминг-конвенция enforced: без аббревиатур и усечённых слов; файл и
  функция команд несут объект операции (`move_change`, `sync_indexes`).
- `transitions-from` — единственный источник переходов для подсказок
  и action-баров; конфиг-дефолты в одной точке.

## Ранее (0.1–0.33.20)

Становление: state machine, tracking/history, TUI-пикер с поиском,
индекс-кэши, plain-режим для Claude Code, lint-субстрат (M8),
доктрины в `roadmap/`. См. `git log`.
