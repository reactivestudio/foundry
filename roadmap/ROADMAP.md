# Foundry — Roadmap

Живой документ. Каждая фаза описана структурно: цель, что добавляем и в каком
компоненте, какие правила начинают действовать, где стоит human gate, что
считается закрытием. Детализация уточняется по мере прохождения — но скелет
всех фаз зафиксирован здесь.

---

## Что строим

Claude Code marketplace plugin, реализующий CRISPY methodology для solo
senior/staff инженера на Kotlin / Spring Boot.

**Источники** (полные документы рядом):
- **[CRISPY.md](CRISPY.md)** — primary канон (Dex Horthy, обновлённый RPI)
- **[12-FACTOR.md](12-FACTOR.md)** — engineering principles
- **[NO-VIBES.md](NO-VIBES.md)** — context engineering для coding agents
- **[MISSIONS.md](MISSIONS.md)** — Validation Contract, structured handoffs, adversarial verifier

---

## Инварианты framework'а

1. **State в файлах, не в LLM-памяти.** Возобновление — из артефактов на диске. ([12-FACTOR §6](12-FACTOR.md), [CRISPY §11](CRISPY.md))
2. **Own your control flow.** State machine на bash, не «промпт решает что дальше». ([12-FACTOR §5](12-FACTOR.md), [CRISPY §8](CRISPY.md))
3. **Каждый агент ≤40 инструкций.** ([CRISPY §1](CRISPY.md))
4. **Артефакт стадии — это её compact** (resume-точка). Никаких отдельных `compact.md`. ([CRISPY §11](CRISPY.md))
5. **Trajectory matters** — failure = first-class артефакт. ([NO-VIBES §4](NO-VIBES.md))
6. **Sub-agents — для изоляции, не для ролей.** ([NO-VIBES §6](NO-VIBES.md), [12-FACTOR §10](12-FACTOR.md))
7. **Система дообучается, но только через approved patches.** Правки человека
   на gate'ах собираются механикой (не дисциплиной); калибровка превращает
   систематические правки в патчи skills/lint; ни один патч не применяется
   без approve. См. «Learning loop» ниже.

---

## Механизмы enforcement

Принципы имеют ценность только если framework их реально enforce'ит:

| # | Механизм | Тип | Где живёт |
|---|----------|-----|-----------|
| M1 | **State machine** | hard (bash) | `scripts/cli/spec/state-machine.sh`, `scripts/cli/store/tracking.sh` |
| M2 | **Tool restrictions** | hard (Claude Code) | `allowed-tools:` в frontmatter агентов/команд |
| M3 | **Sub-agent isolation** | structural | Task tool invocation с restricted prompt |
| M4 | **Bash wrappers** | hard (через allowed-tools) | build/test-обёртки под сборщик целевого проекта |
| M5 | **Hooks** | intervention | `hooks/*.sh` через `hooks.json` |
| M6 | **Agent prompts** | soft | тело `agents/*.md` |
| M7 | **Skill content** | soft | `skills/**/SKILL.md` |
| M8 | **Validation scripts** | post-action | `scripts/cli/spec/lint/*.sh` на stage gate |
| M9 | **Frontmatter config** | declarative | `model:`, `allowed-tools:`, `description:` |
| M10 | **Calibration loop** | gated feedback | `.foundry/feedback/` + `/foundry:calibrate` |

**Hard** — нельзя обойти. **Soft** — агент следует, потому что так написано в
prompt. Один принцип enforce'ится несколькими слоями сразу — см. worked
example в конце документа.

---

## Learning loop — как система дообучается

Каждый human gate производит не только «дальше/назад», но и обучающий сигнал.
Цикл:

1. **Снапшот.** Когда стадия переходит `active → review`, CLI снимает копию
   артефакта. Механика, не дисциплина: сигнал собирается всегда.
2. **Дельта.** Человек правит артефакт прямо во время ревью (или approve'ит
   как есть). На переходе `review → completed` CLI diff'ает снапшот с
   финальной версией и пишет дельту в `.foundry/feedback/<stage>/` +
   событие в history. Approve без правок — тоже сигнал («образец хорошего»).
3. **Калибровка.** `/foundry:calibrate <stage>` — LLM-команда: читает
   накопленные дельты стадии, ищет систематику (одна и та же правка ≥2 раз)
   и предлагает патч:
   - урок, выразимый детерминированной проверкой → **lint-правило (M8)**;
   - урок-формулировка («в design всегда фиксировать rollback-план») →
     **skill стадии (M7)** или инструкция агенту (M6) — с учётом бюджета ≤40;
   - проектно-специфичный урок → аддендум в `.foundry/skills/<stage>.md`
     целевого проекта (плагин читает его поверх глобального skill).
4. **Meta-gate.** Патч применяется только после approve. Skills под git —
   откат тривиален. `instruction-count` на CI не даёт калибровке раздуть
   промпты.

Правило приоритета: всё, что можно выразить lint'ом — выражаем lint'ом;
skill — для того, что проверке не поддаётся; ничего не остаётся «в голове».

---

## Pipeline (target shape)

CRISPY 8 фаз + verify из Missions. Документация — не отдельная стадия:
CHANGELOG/README-правки входят в PR (стадия 9), ADR и грабли — в память
инженера вне репозитория.

| # | Стадия | Producer | LLM? | Human gate |
|---|--------|----------|------|------------|
| 1 | questions | questioner | yes | — |
| 2 | research | researcher (+ sub-agent) | yes | — |
| 3 | design | designer | yes | **Deep review** (~200 строк) |
| 4 | structure | outliner | yes | Spot-check |
| 5 | plan | planner (per task) | yes | Spot-check |
| 6 | worktree | bash | no | — |
| 7 | implement | implementor (per task) | yes | **Code review** |
| 8 | verify | verifier (fresh, adversarial) | yes | Approve report |
| 9 | pr + docs | bash + template | no | Final approve |

[CRISPY §12](CRISPY.md) — стадии; [MISSIONS §5](MISSIONS.md) — adversarial verifier.

---

## Категории компонентов

Каждая фаза описывает deliverables в этих категориях:

| Категория | Что это | Где живёт |
|---|---|---|
| Скрипты | bash-логика, вся детерминированная механика | `scripts/cli/*` |
| Агенты | producer-промпты стадий, ≤40 инструкций | `agents/*.md` |
| Skills | контракты и справочники для LLM | `skills/**/SKILL.md` |
| Команды | промпт-адаптеры входа из сессии Claude Code | `commands/*.md` |
| Правила | enforcement-проводка: что с этой фазы нельзя обойти | M1–M10 |
| Артефакты | файлы, появляющиеся в change целевого проекта | `.foundry/changes/<slug>/` |
| Калибровка | вклад фазы в learning loop | `.foundry/feedback/`, skills |

---

## Статус фаз

| Фаза | Содержание | Статус |
|---|---|---|
| 0 | Plugin skeleton | ✅ закрыта |
| 1 | Change lifecycle (bucket-уровень, no LLM) | код готов; **STOP открыт: dogfood** |
| 2 | Стадийный субстрат: stage state machine + lint + feedback | следующая |
| 3 | Стадии questions + research | — |
| 4 | Стадия design + Validation Contract + первый calibrate | — |
| 5 | Стадия structure | — |
| 6 | plan + worktree + implement + pr/docs | — |
| 7 | Стадия verify | — |
| 8 | /quickfix bypass | — |
| 9 | Интеграции: Jira ↔ foundry | — |
| 10 | Domain layer: Kotlin / Spring / distributed | — |
| 11 | Marketplace polish + model per role | — |

### Параллельный трек: foundry-desktop (обязателен — ревью живёт в нём)

Ревью артефактов — обязательная часть системы, поэтому приложение — не
«потом», а параллельный трек с вехами, синхронизированными с фазами ядра.
Концепт и архитектура — [foundry-desktop.md](foundry-desktop.md); отдельный
репозиторий; стек (Compose for Desktop vs Spring Boot + SPA) решить до D1.

| Веха | Содержание | Синхронизация с ядром |
|---|---|---|
| D0 | Спайк петли: fs-watch `.foundry/`, рендер артефакта, approve через CLI, прогон `claude -p` | параллельно фазе 2 |
| D1 | **Review MVP**: change'и проекта, артефакт стадии, diff снапшот↔текущий, комментарии с метками, approve / request-changes | готов к первым артефактам (фаза 3), **обязателен к фазе 4** |
| D2 | Оркестрация: запуск стадий из приложения, live-статус, доска по статусам | фазы 5–6 |
| D3 | Калибровка UI: очередь дельт, черновики патчей, approve | вместе с первым calibrate (фаза 4+), полноценно к фазе 7 |
| D4 | Аналитика (счётчик лупов) + мультипроект (инбокс ревью) | после фазы 6 |

Ревью в `$EDITOR` остаётся как escape-hatch (механика снапшот/дельта/вердикт
одна и та же) — но целевая поверхность ревью с D1 — приложение.

---

## Phase 0 — Plugin skeleton ✅

Валидный пустой marketplace-плагин: manifest'ы, скелет директорий, README.
Закрыта: `claude plugin validate` чистый, установка локально работает.

---

## Phase 1 — Change lifecycle framework (no LLM)

**Цель:** управлять change'ами полностью без LLM. Substrate + первый hard
enforcement (M1) на bucket-уровне.

**Сделано:**

| Категория | Что есть |
|---|---|
| Скрипты | слои `scripts/cli/`: config / spec (state-machine, slug, lint) / store (change CRUD, tracking, index, query) / render / commands / pages; TUI-пикер; `--plain` |
| Команды | `/foundry:change`, `/foundry:setup` — адаптеры без логики, мутации только через CLI |
| Skills | `spec/lifecycle`, `spec/naming`, `spec/lint` |
| Правила | M1: переходы статуса только через state machine; serial execution (один in-progress); `done` терминален; decline требует причину |
| Артефакты | `proposal.md`, flat `tracking.yaml`, append-only `history.log` |
| Качество | 107 проверок в 4 сьютах (`tests/`), CI ubuntu+macos (bash 3.2), pre-commit hook, shellcheck-чистота |

**STOP (открыт):** прогнать реальный change на живом проекте:
`foundry new` → работа → `move done`. Собрать трение — оно входной материал
для фазы 2. Не начинаем фазу 2 до этого.

---

## Phase 2 — Стадийный субстрат: stages + lint + feedback

**Цель:** вся механика, на которой живут LLM-стадии, — до того как написан
первый агент. Stage-уровень state machine (M1), полный lint-набор (M8),
сбор feedback-дельт (M10-основание).

**Enforcement-вклад:** M1 расширяется на стадии; M8 полный; M10 — сбор сигнала.

| Категория | Добавляем |
|---|---|
| Скрипты | `store/tracking.sh`: `add-stage` / `set-stage` / список стадий в `tracking.yaml`; `spec/state-machine.sh`: stage-переходы `required → active → review → completed` (+ `skipped`), снапшот артефакта на `active → review`, дельта на `review → completed`; `store/feedback.sh`: запись/чтение дельт; `spec/lint/instruction-count.sh` (бюджет ≤40 на агента), `spec/lint/horizontal-pattern.sh` (vertical plans); уже есть: `line-count.sh`, `opinion-words.sh` |
| Команды | — (субстрат не имеет пользовательского входа, кроме существующих) |
| Правила | `set-stage completed` невозможен без прохождения lint-гейта стадии и без артефакта; CI гоняет `instruction-count` на `agents/*.md` (пока их нет — правило ждёт первых агентов) |
| Артефакты | `stages:` в `tracking.yaml`; `feedback/<stage>/` в сторе проекта |
| Хранилище | **переезд в глобальный стор**: `~/.foundry/projects/<id>/`, поиск проекта обходом `projects/*/project.yaml` (реестра нет — это был бы второй список тех же проектов; worktree'ы через `git-common-dir`); статус — поле в `tracking.yaml`, не каталог; в репозитории проекта — ничего; `setup` = скелет `.store/` → `~/.foundry/` + `projects/<id>/` + permissions `~/.foundry/**`. Раскладка — [components.md](components.md#хранилище-данных--глобальное-одна-точка-правды). Мигрировать до первых артефактов — пустое хранилище дешевле живого |
| Калибровка | дельты собираются механикой с первой же LLM-стадии; формат записи: verdict (approved / edited / rejected) + diff + опциональная нота человека |

**Проверки:** stage-переходы валидируются и покрыты тестами; снапшот/дельта
работают на искусственном артефакте; все четыре lint'а имеют тесты;
инвалидный stage-переход невозможен из CLI и из `/foundry:change`.

**STOP:** lint-набор и stage-механика полностью покрыты тестами на обеих
платформах CI. Ни одного агента в этой фазе не пишем.

---

## Phase 3 — Стадии questions + research

**Цель:** первая пара LLM-стадий и главная инновация CRISPY — изоляция
research от задачи ради фактов вместо мнений. ([CRISPY §3](CRISPY.md))

**Enforcement-вклад:** M2 + M3 + M6 + M7 впервые в бою, M8 подключается к стадиям.

| Категория | Добавляем |
|---|---|
| Скрипты | проводка стадий в CLI: `foundry show` отображает стадии и их состояние; stage-подсказки из state machine |
| Агенты | `agents/questioner.md` — видит proposal, генерирует вопросы к кодебазе без упоминания решения; `agents/researcher.md` — видит **только вопросы**, отвечает фактами `file:line`, делегирует чтение кодебазы sub-agent'у (M3) |
| Skills | `skills/spec/questions-contract/SKILL.md`, `skills/spec/research-contract/SKILL.md` — формат, анти-паттерны, примеры |
| Команды | `commands/stage.md` — `/foundry:stage`: запустить следующую стадию активного change; какая стадия следующая — решает state machine, не LLM |
| Правила | M2: researcher и его sub-agent в `allowed-tools:` **не имеют** `Read(proposal.md)`; M8 на gate: `opinion-words` + `line-count ≤30` для research; M1: `review → completed` только человеком |
| Артефакты | `questions.md`, `research.md` |
| Калибровка | дельты по обеим стадиям копятся с первого прогона (механика фазы 2) |

**Проверки:** на реальном change: questions не содержит решения; research —
только факты, lint зелёный; попытка researcher'а прочитать proposal
блокируется allowed-tools.

**STOP:** пара questions/research прогнана на ≥2 реальных change'ах и
дельты записались.

---

## Phase 4 — Стадия design + Validation Contract + первая калибровка

**Цель:** главный leverage point — ~200 строк, которые человек читает
внимательно ([CRISPY §4](CRISPY.md)); testable-критерии до кода
([MISSIONS §4](MISSIONS.md)); первое замыкание learning loop.

**Enforcement-вклад:** M1 (гейт на артефакт-зависимость), M10 полный цикл.

| Категория | Добавляем |
|---|---|
| Скрипты | state machine: `design → completed` требует существующего `validation-contract.md` |
| Агенты | `agents/designer.md` — current state / desired end state / patterns to follow / resolved decisions / open questions |
| Skills | `skills/spec/design-contract/SKILL.md` (структура, ≤220 строк), `skills/spec/validation-contract/SKILL.md` (что такое testable-критерий) |
| Команды | `commands/calibrate.md` — `/foundry:calibrate <stage>`: анализ дельт → предложение патча → approve → применение |
| Правила | M8: `line-count ≤220` на design; M1: без validation contract стадия не закрывается; M10: патчи skills/lint только через approve |
| Артефакты | `design.md`, `validation-contract.md` |
| Калибровка | **первый рабочий цикл**: правки design'а на deep review → дельты → calibrate → патч design-contract skill или новое lint-правило |

**Human gate:** deep review design'а — главная точка вложения внимания.

**Проверки:** design ≤220 строк проходит lint; без VC не закрывается;
calibrate на накопленных дельтах предлагает осмысленный патч; патч без
approve не применяется.

**STOP:** design-стадия прогнана на реальном change, deep review дал правки,
calibrate превратил их в патч, патч принят и виден в git.

---

## Phase 5 — Стадия structure

**Цель:** vertical outline — «C header file» изменения: фазы имплементации,
порядок, как тестируем после каждой. ([CRISPY §5, §6](CRISPY.md))

| Категория | Добавляем |
|---|---|
| Агенты | `agents/outliner.md` — vertical-фазы, каждая компилируется и тестируется |
| Skills | `skills/spec/structure-contract/SKILL.md` |
| Правила | M8: `line-count ≤100` + `horizontal-pattern` (лестница «вся БД → весь сервис → весь API» = fail) |
| Артефакты | `structure.md` |
| Калибровка | дельты spot-check'а копятся; calibrate доступен для стадии |

**Human gate:** spot-check.

**STOP:** structure на реальном change прошла lint и spot-check без
переделки более одного раза.

---

## Phase 6 — plan + worktree + implement + pr/docs

**Цель:** исполнительный контур: тактический план per task, изолированная
ветка, имплементация vertical-слайсами, PR с документацией.
([CRISPY §7](CRISPY.md), [MISSIONS §6](MISSIONS.md))

**Enforcement-вклад:** M4 впервые (build/test-обёртки), M8 schema validation.

| Категория | Добавляем |
|---|---|
| Скрипты | worktree-механика (git branch, mechanical); build/test-обёртки под сборщик целевого проекта — compact errors: PASS/FAIL + первые 20 строк ([12-FACTOR §7](12-FACTOR.md)); PR-шаблон; schema-валидация плана и handoff'ов |
| Агенты | `agents/planner.md` — план ≤7 шагов со снипетами до/после; `agents/implementor.md` — per-task, structured handoff на выходе |
| Skills | `skills/spec/plan-contract/SKILL.md`, `skills/spec/handoff/SKILL.md` (Missions schema) |
| Команды | расширение `/foundry:stage` на исполнительные стадии; diff-просмотр перед approve («read the code», [CRISPY §9](CRISPY.md)) |
| Правила | M2: сборщик напрямую запрещён — только через обёртки; M8: план и handoff валидируются схемой; M1: implement не закрывается без зелёного verify... (гейт стадии 8) |
| Артефакты | `plan/<task>.md`, handoff-записи, PR body; CHANGELOG/README-правки — часть того же PR |
| Калибровка | дельты code review — самый богатый сигнал: систематические правки кода → патчи implement-skill и доменных skills (фаза 10) |

**Human gates:** spot-check плана; **code review** (читаем код, не план);
final approve PR.

**STOP:** полный проход стадий 5–9 на реальном change: от плана до
смерженного PR с обновлённой документацией.

---

## Phase 7 — Стадия verify

**Цель:** adversarial-проверка свежим контекстом: verifier не видит design и
plan — только validation contract и код. ([MISSIONS §3, §5](MISSIONS.md))

| Категория | Добавляем |
|---|---|
| Агенты | `agents/verifier.md` — fresh context, проверяет код против validation contract |
| Skills | `skills/spec/verify-contract/SKILL.md` — формат отчёта: PASS/FAIL per критерий |
| Правила | M2: в `allowed-tools:` verifier'а нет `design.md` и `plan/`; M1: change не уходит в `done` без approved verify-отчёта |
| Артефакты | `verify-report.md` |
| Калибровка | FAIL'ы verify — сигнал против implement: то, что verifier ловит систематически, должно стать lint'ом или правкой implement-skill |

**Human gate:** approve отчёта.

**STOP:** verify поймал хотя бы одну реальную проблему, которую пропустил
code review, — или два change'а подряд прошли verify чисто.

---

## Phase 8 — /quickfix bypass

**Цель:** тривиальным задачам не нужен конвейер — но нужен учёт и гейт.
([NO-VIBES §14](NO-VIBES.md))

| Категория | Добавляем |
|---|---|
| Команды | `commands/quickfix.md` — `/foundry:quickfix`: change создаётся, стадии 1–5 помечаются `skipped`, сразу implement |
| Правила | M1: bypass стадий ≠ bypass state machine — change существует, история пишется, гейт на выходе (diff review) обязателен |
| Калибровка | если quickfix регулярно перерастает в полный change — сигнал, что классификация «тривиально» врёт; видно из history |

**STOP:** quickfix реально быстрее ручного объезда — иначе им не будут
пользоваться.

---

## Phase 9 — Интеграции: Jira ↔ foundry

**Цель:** замкнуть внешний контур: задача рождается в Jira, результат
возвращается в Jira; двойной ввод исчезает.

| Категория | Добавляем |
|---|---|
| Скрипты | поле `jira_key` в `tracking.yaml`; шаблон учитывает его с фазы 2 (миграций нет — поле опциональное) |
| Команды | `commands/jira.md` — промпт-адаптер поверх Atlassian MCP: `new --from-jira <key>` (title + proposal из задачи), синк при `move` (in-progress → Jira In Progress), закрытие (комментарий с результатом + worklog + transition в Done) |
| Правила | foundry — источник правды, Jira догоняет; маппинг статусов: To Do ↔ backlog, In Progress ↔ in-progress, Done ↔ done, Won't Do ↔ declined; синк — побочный эффект команд, не отдельная дисциплина |
| Артефакты | ссылка на Jira-задачу в `tracking.yaml` и в PR body |

**STOP:** реальная задача прошла Jira → foundry → PR → Jira Done без ручного
дублирования текста.

---

## Phase 10 — Domain layer: Kotlin / Spring / distributed

**Цель:** доменные skills целевого стека. Наполняются не «из головы», а из
калибровки: систематические правки code review (фазы 6–7) — основной
источник контента.

| Категория | Добавляем |
|---|---|
| Skills | `skills/domain/kotlin/`, `skills/domain/spring/`, `skills/domain/distributed/` — паттерны, анти-паттерны, выбор инструментов |
| Правила | M7: implementor подключает доменные skills по типу задачи; бюджет инструкций считается суммарно (CI) |
| Калибровка | это фаза-потребитель learning loop: дельты фаз 6–7 конвертируются в доменные skills |

**STOP:** на реальном change видно снижение числа правок code review
по сравнению с фазой 6 (метрика — из feedback-историй).

---

## Phase 11 — Marketplace polish + model per role

**Цель:** публикация и оптимизация стоимости/качества per-стадия.
([MISSIONS §9](MISSIONS.md))

| Категория | Добавляем |
|---|---|
| Правила | M9: `model:` frontmatter per агент — дешёвая модель для механических стадий, сильная для design/verify |
| Прочее | manifest polish, инструкция установки, версия 1.0 |

**STOP:** плагин ставится «с нуля» по README на чистой машине.

---

## Что фреймворк НЕ enforce'ит (осознанно)

| Правило | Источник | Почему не enforce | Замена |
|---|---|---|---|
| Smart Zone (≤35–60% context fill) | [NO-VIBES §5](NO-VIBES.md) | Real token count недоступен; порог fuzzy; Goodhart's law | `/context` + привычка |
| «Wrap up при degradation» | [NO-VIBES §1, §4](NO-VIBES.md) | Качественный признак, не число | Суждение инженера |
| Trajectory protection (>2 ошибки = новый контекст) | [NO-VIBES §4](NO-VIBES.md) | stderr-детекция шумная; потребителя нет до фазы 6 | Дисциплина; пересмотреть на фазе 6 |
| Compaction infra | [CRISPY §11](CRISPY.md) | Артефакты стадий = resume-точки | — |

---

## Worked example: research isolation

Правило ([NO-VIBES §6](NO-VIBES.md), [CRISPY §3](CRISPY.md)): research
возвращает факты `file:line`, ≤30 строк, без opinion'ов, **без знания задачи**.

Enforce'им пятью механизмами одновременно:

1. **M2:** researcher имеет `allowed-tools: Read(questions.md), Read(src/**), Grep, Glob` — **права читать `proposal.md` нет**.
2. **M3:** чтение кодебазы делегируется sub-agent'у — свежий контекст, тоже без proposal.
3. **M6:** `agents/researcher.md` специфицирует формат и запрещённые слова.
4. **M7:** `skills/spec/research-contract/SKILL.md` — контракт + анти-паттерны.
5. **M8:** `opinion-words.sh` + `line-count.sh` на gate — `set-stage research completed` невозможен при fail.

Убери любой слой — дисциплина ослабевает; вместе — агент может проигнорировать
prompt, но не может обойти M2 + M8. **Это и есть «framework enforce'ит
доктрину».** С фазы 4 к этому добавляется M10: правки человека на gate'ах
делают каждый следующий прогон стадии лучше предыдущего.

---

## Open questions

- Формат feedback-дельты: полный unified diff или структурированная запись
  (verdict + суть правки)? Решаем на фазе 2 по первым реальным дельтам.
- Проектные аддендумы skills (`.foundry/skills/<stage>.md`): читать всегда
  или по opt-in в config? Решаем на фазе 4.
- Jira-маппинг кастомных статусов (не стандартный workflow) — на фазе 9.
- Метрика качества стадии (доля approve-без-правок?) — не раньше фазы 6,
  когда появится статистика.

---

*Фаза не закрыта, пока на ней не прогнан реальный change. Правки человека на
gate'ах — не накладной расход, а топливо калибровки.*
