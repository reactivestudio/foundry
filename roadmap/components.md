# foundry — Карта компонентов

> Живая карта: из чего состоит система, как change обрастает артефактами по
> стадиям, и где живёт машина самоулучшения. Верхний слой — [REQUIREMENTS.md](REQUIREMENTS.md)
> (что и зачем), [ROADMAP.md](ROADMAP.md) (фазы), [foundry-desktop.md](foundry-desktop.md)
> (приложение). `★` = узлы, обеспечивающие самоулучшение.

---

## Вход → агент → выход по стадиям

| Стадия | Вход | Агент | Выход (артефакт) | Ревью |
|---|---|---|---|---|
| questions | `proposal.md` | questioner | `questions.md` — вопросы к коду | — |
| research | `questions.md` (без proposal) | researcher + scout | `research.md` — факты `file:line` | — |
| design | proposal + research | designer | `design.md` + `validation-contract.md` | глубокое, человек |
| structure | `design.md` | outliner | `structure.md` = список задач | spot-check |
| *далее — по каждой задаче* | | | | |
| plan | одна задача | planner | `plan/<task>.md` — шаги + до/после | spot-check |
| worktree | — | bash | git-ветка | — |
| implement | `plan/<task>.md` + код | implementor | код (diff) + handoff | code review, человек |
| verify | `validation-contract.md` + код (без design/plan) | verifier | `verify-report.md` — PASS/FAIL | approve |
| pr | всё | bash | PR + доки | финальный approve |

**Атомарная задача** — выход стадии structure: вертикальный слайс, который
компилируется и проходит тесты сам по себе (разбить дальше — сломается). По
каждой задаче отдельно крутится plan → implement → verify.

**Цикл ревью:** артефакт → `review` → замечания или approve. Есть замечания →
агент переделывает → снова `review`. По кругу до нуля замечаний → `completed`.

---

## Плагин `foundry` (этот репозиторий)

Движок + агенты + скиллы + правила.

```
foundry/
├── .claude-plugin/
│   ├── plugin.json  marketplace.json          # паспорт плагина
│
├── agents/                                    # промпты стадий (≤40 инструкций)
│   ├── questioner.md        # proposal → questions
│   ├── researcher.md        # questions → research (без proposal)
│   ├── research-scout.md    # нырок в код для researcher
│   ├── designer.md          # research+proposal → design + критерии
│   ├── outliner.md          # design → список задач
│   ├── planner.md           # задача → план
│   ├── implementor.md       # план+код → код
│   ├── verifier.md          # критерии+код → PASS/FAIL
│   └── calibrator.md   ★    # дельты → черновик правки skill/agent/rule
│
├── skills/
│   ├── spec/                                  # контракты стадий: как + чего нельзя
│   │   ├── questions-contract/  research-contract/  design-contract/
│   │   ├── validation-contract/ structure-contract/ plan-contract/
│   │   ├── verify-contract/  naming-guide/  lifecycle-reference/  lint-guide/
│   └── domain/                                # Kotlin/Spring/SOLID — растут из калибровки
│       └── kotlin-guide/  spring-guide/  solid-guide/
│            └─ SKILL.md: в шапке ЗОНА скилла   # ★ за что отвечает (для атрибуции правок)
│
├── commands/                                  # входы человека в сессию Claude
│   ├── change.md  setup.md  stage.md
│   ├── calibrate.md    ★    # просмотр и approve черновиков улучшений
│   └── quickfix.md  jira.md
│
├── hooks/
│   ├── hooks.json
│   └── on-stage-complete.sh  ★                # авто-триггер: снимок + запись дельты
│
├── scripts/cli/                               # bash-движок, слоями
│   ├── app                                    # загрузка + диспетчер
│   ├── config/              # реестр бакетов, дефолты, ПОРОГИ калибровки ★
│   ├── spec/                                  # правила CRISPY
│   │   ├── state-machine.sh                   # переходы — единственный источник
│   │   ├── slug.sh
│   │   ├── stages/     ★    # на стадию: какие скиллы грузим + какие гейты
│   │   │   └── questions.yaml research.yaml design.yaml … verify.yaml
│   │   ├── calibrate.sh ★   # считает повторы, проверяет порог, зовёт calibrator
│   │   └── lint/           # валидаторы = инструменты для правил
│   │       └── line-count.sh opinion-words.sh instruction-count.sh horizontal-pattern.sh
│   ├── store/                                 # данные
│   │   ├── change.sh tracking.sh query.sh template.sh index_cache.sh
│   │   └── feedback.sh  ★   # пишет/читает снимки и дельты
│   ├── render/             # рисование TUI
│   ├── commands/           # plain-подкоманды (cmd_*)
│   └── pages/              # интерактивные экраны
│
├── tests/                  # сьюты + harness + раннер
├── roadmap/                # CRISPY 12-FACTOR NO-VIBES MISSIONS · ROADMAP REQUIREMENTS foundry-desktop components
└── CLAUDE.md               # нейминг-доктрина
```

---

## Хранилище данных — глобальное, одна точка правды

**Решение:** данные живут НЕ в папке проекта, а в глобальном сторе (как
проекты claude-desktop). В репозитории проекта — ничего (ни данных, ни
симлинков); AI-процесс не касается git проекта вовсе. Данные переживают
re-clone и перенос проекта. Durable-«почему» уезжает в PR/CHANGELOG/vault.

```
~/.foundry/
├── registry.yaml                        # cwd → id (резолв проекта)
└── projects/<id>/
    ├── project.yaml                     # путь, имя, метаданные проекта
    ├── changes/
    │   ├── backlog/ in-progress/ done/ declined/   # бакет = каталог: атомарный
    │   │   │                                       # mv, ls без парсинга имён
    │   │   └── <slug>/
    │   │       ├── proposal.md              # спека change (вход questioner)
    │   │       ├── tracking.yaml            # состояние + стадии + история
    │   │       ├── history.log
    │   │       ├── inputs/                  # внешние материалы change'а:
    │   │       │                            # тикет, логи, схемы, заметки —
    │   │       │                            # не произведены стадиями, ссылаются любой
    │   │       └── stages/                  # артефакты по стадиям, с порядком
    │   │           ├── 01-questions/
    │   │           │   ├── questions.md         # текущая рабочая версия
    │   │           │   ├── inputs.yaml          # манифест ССЫЛОК: что дано на вход
    │   │           │   │                        # (артефакты любых стадий, inputs/,
    │   │           │   │                        # файлы кода, URL) — не копии
    │   │           │   ├── versions/vN-<date>.md ★ # вывод агента на лупе N
    │   │           │   └── reviews/vN-<date>.md  ★ # твои замечания к лупу N
    │   │           ├── 02-research/         # research.md + versions/ + reviews/
    │   │           ├── 03-design/           # design.md + validation-contract.md
    │   │           ├── 04-structure/        # structure.md (= задачи)
    │   │           ├── 05-plan/             # <task>.md на задачу
    │   │           ├── 06-implement/        # handoff'ы; код — в git-ветке
    │   │           └── 07-verify/           # verify-report.md
    │   ├── .template/
    │   └── feedback/<stage>.jsonl        ★  # накопленные дельты (сигнал калибровки)
    └── skills/<stage>.md                 ★  # проектные добавки к скиллам

Правила раскладки стадий:
- **Версия = номер лупа** (наша же метрика «лупов всё меньше» видна глазами),
  дата — суффикс для человека; пара `versions/vN` ↔ `reviews/vN` — единица,
  из которой калибровка берёт дельту. `versions/` заменяет прежние снапшоты.
- **Вход стадии — откуда угодно, но ссылками, не копиями.** Входы разнородны:
  артефакты любых стадий (не только предыдущей), внешние материалы
  (`<slug>/inputs/`: тикет, логи, схемы), код проекта, URL. Дефолтный набор
  объявлен в `spec/stages/<stage>.yaml`; что реально дано на прогоне —
  манифест `stages/<NN>/inputs.yaml` (воспроизводимость + атрибуция
  калибровки). Чужие выходы никогда не копируются — одна правда, ноль дублей.
- **Статус — только каталогом-бакетом**, не префиксом в имени: `[...]` —
  метасимвол глоббинга в bash (мина под каждый скрипт), а каталог даёт
  атомарный `mv` и листинг без парсинга.
```

Механика доступа:
- **Права** — один раз на пользователя: `~/.foundry/**` в permissions
  (`settings.json`); изоляция стадий — абсолютными паттернами в
  `allowed-tools` (researcher: `questions.md` можно, `proposal.md` нельзя).
- **Резолв проекта** — CLI: cwd → `registry.yaml` → `projects/<id>`;
  worktree'ы — через `git rev-parse --git-common-dir` (один репозиторий =
  один id). Перенос/переименование проекта = обновить запись в реестре.
- **Desktop** — сканирует `~/.foundry/projects/`, отдельный реестр проектов
  как фича не нужен.
- **Плагин** глобален по определению (ставится один раз); `setup` теперь =
  регистрация проекта в реестре + скаффолд `projects/<id>/` + permissions.

---

## Приложение `foundry-desktop` (отдельный репозиторий, Kotlin)

Стек ещё открыт (Compose for Desktop или Spring Boot + SPA, на хосте, без Docker).

```
foundry-desktop/
├── реестр проектов + слежение за .foundry/ (fs-watch)
├── оркестратор — шеллит foundry, гоняет claude -p
├── ревью-интерфейс — правки, diff, комментарии, loop
├── калибровка — черновики улучшений → твой approve
├── аналитика — счётчик лупов (он же сигнал улучшения)
└── локальная БД — проекция: индекс, треды ревью, история дельт, настройки
```

Связь двух репозиториев — только через файлы `.foundry/` и вызовы CLI:
приложение можно менять, не трогая ядро.

---

## Машина самоулучшения (узлы `★`, поток)

На **каждом** витке ревью, автоматически:

1. `hooks/on-stage-complete.sh` — снимает снимок вывода агента → `.snapshots/`.
2. ты правишь и комментируешь → `reviews/<stage>.md` (правки + метки тем).
3. `store/feedback.sh` — пишет дельту (что изменилось) + чем произведено
   (агент, скиллы, правила) → `feedback/<stage>.jsonl`.
4. `spec/calibrate.sh` — копит, ловит повтор одной правки ≥ N (порог в `config/`).
5. `agents/calibrator.md` — рисует черновик правки; цель — **любое из наших**:
   скилл / промпт агента / правило (что именно — из метки темы vs зоны скилла).
6. `commands/calibrate.md` — ты просматриваешь и одобряешь; git хранит и
   откатывает.

Автоматически: снимок, запись дельты, проверка порога, черновик. Твоё: ревью и
финальный approve. Единственное, что не автоматизировано, — суждение.

**Атрибуция** (какой скилл виноват, если их несколько): метка темы правки →
зона скилла (объявлена в его шапке). Один совпал → правим его; двое →
перекрытие зон, правим границу; ни один → новый скилл; нет повтора → не про
скиллы (агент/задача).
