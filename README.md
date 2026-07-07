# Foundry

[![ci](https://github.com/reactivestudio/foundry/actions/workflows/ci.yml/badge.svg)](https://github.com/reactivestudio/foundry/actions/workflows/ci.yml)

Claude Code marketplace plugin реализующий CRISPY methodology для solo senior/staff инженера на Kotlin / Spring Boot. Источники канона: [CRISPY](roadmap/CRISPY.md) (primary), [12-Factor Agents](roadmap/12-FACTOR.md), [No Vibes Allowed](roadmap/NO-VIBES.md), [Missions](roadmap/MISSIONS.md). Текущий план — [roadmap/ROADMAP.md](roadmap/ROADMAP.md).

Ядро — change-lifecycle на чистом bash (3.2+, ноль внешних зависимостей):
изменения живут в `.foundry/changes/{backlog,in-progress,done,declined}/<slug>/`,
переходы валидирует детерминированная state machine, а не LLM.

## Два входа, один субстрат

- **Терминал (человек):** `./foundry` — интерактивный TUI (пикер, поиск,
  drill-down); `--plain` — детерминированный вывод для скриптов.
- **Сессия Claude Code (LLM):** `/foundry:change`, `/foundry:setup` —
  промпт-адаптеры поверх тех же скриптов; мутации только через state
  machine, human gate на переходах.

## Установка в проект

Из сессии Claude Code с установленным плагином:

```
/foundry:setup        # скаффолд .foundry/ + опционально CLI-симлинки
```

или из терминала (изнутри каталога плагина):

```bash
cli --plain setup --install-cli
```

После этого в корне проекта появляются `./foundry` и `./f` (симлинки,
добавлены в .gitignore автоматически).

## CLI

```
foundry                          интерактивный TUI: пикер изменений
foundry list [--bucket=X] [--sort=K] [--reverse]
foundry show <slug>              метаданные + история + next-подсказки
foundry new ["title"]            создать change в backlog
foundry move <slug> --to=X [--reason=R]
foundry sync                     пересобрать индексы бакетов
foundry setup [--install-cli]    скаффолд .foundry/
foundry version                  версия плагина
```

Глобальный флаг `--plain` — ASCII без цветов и промптов (автоматически,
когда stdout не TTY). Exit-коды: `0` успех · `1` отказ домена (переход
запрещён, не найдено) · `2` проблема окружения · `64` usage.

Клавиши TUI: ввод текста — фильтр; `↑/↓` — курсор; `Tab` — следующий
бакет; `↵` — выбрать; `⎋` — назад/выход.

## Гарантии

- Переходы — только через state machine (serial invariant: максимум
  один change в in-progress; `done` терминален; decline требует reason).
- Подсказки `show` и action-бар detail-страницы генерятся из той же
  таблицы переходов — UI не может разойтись с машиной.
- Свободный текст санитизируется на записи: flat-YAML и TSV-схемы
  не ломаются враждебным title/reason.

## Разработка

```bash
git config core.hooksPath scripts/githooks   # pre-commit: shellcheck + тесты
scripts/test/smoke.sh                        # e2e CLI (plain)
scripts/test/picker.sh                       # внутренности пикера без TTY
scripts/test/store.sh                        # yaml/index/template/slug
scripts/test/pages.sh                        # построение страниц без TTY
```

CI гоняет всё на ubuntu (bash 5.x, GNU) и macos (`/bin/bash` 3.2) —
обе платформы целевые. История изменений — [CHANGELOG.md](CHANGELOG.md).
