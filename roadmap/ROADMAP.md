# Foundry — Roadmap

Живой документ. Сейчас детализированы только первые две фазы — **фреймворк**, в котором будем работать. Остальное намечено одной строкой каждое, детализируется по мере прохождения.

---

## Что строим

Claude Code marketplace plugin, реализующий CRISPY methodology для solo senior/staff инженера на Kotlin / Spring Boot.

**Источники** (полные документы в корне):
- **[CRISPY.md](CRISPY.md)** — primary канон (Dex Horthy, обновлённый RPI)
- **[12-FACTOR.md](12-FACTOR.md)** — engineering principles
- **[NO-VIBES.md](NO-VIBES.md)** — context engineering для coding agents
- **[MISSIONS.md](MISSIONS.md)** — Validation Contract, structured handoffs, adversarial verifier

---

## Инварианты framework'а (применяем с Phase 0)

1. **State в файлах, не в LLM памяти.** Возобновление — из артефактов на диске. ([12-FACTOR §6](12-FACTOR.md), [CRISPY §11](CRISPY.md))
2. **Own your control flow.** State machine на bash, не «промпт решает что дальше». ([12-FACTOR §5](12-FACTOR.md), [CRISPY §8](CRISPY.md))
3. **Каждый агент ≤40 инструкций** (применимо начиная с Phase 2). ([CRISPY §1](CRISPY.md))
4. **Артефакт стадии — это её compact** (resume точка). Никаких отдельных `compact.md`. ([CRISPY §11](CRISPY.md))
5. **Trajectory matters** — failure = first-class артефакт, не «продолжаем в том же контексте». ([NO-VIBES §4](NO-VIBES.md))
6. **Sub-agents — для изоляции, не для ролей.** Только researcher как sub-agent. ([NO-VIBES §6](NO-VIBES.md), [12-FACTOR §10](12-FACTOR.md))

---

## Правила и enforcement — как доктрина становится кодом

Принципы из 4 докладов имеют ценность **только если framework их реально enforce'ит**, не просто документирует. У нас 9 типов механизмов:

| # | Механизм | Тип | Где живёт |
|---|----------|-----|-----------|
| M1 | **State machine** | hard (bash) | `scripts/tracking.sh`, `scripts/state-machine.sh` |
| M2 | **Tool restrictions** | hard (Claude Code) | `allowed-tools:` в frontmatter агентов/команд |
| M3 | **Sub-agent isolation** | structural | Task tool invocation с restricted prompt |
| M4 | **Bash wrappers** | hard (через allowed-tools) | `scripts/build-check.sh`, `test-check.sh` |
| M5 | **Hooks** | intervention | `hooks/*.sh` через `hooks.json` |
| M6 | **Agent prompts** | soft | тело `agents/*.md` |
| M7 | **Skill content** | soft | `skills/**/SKILL.md` |
| M8 | **Validation scripts** | post-action | `scripts/lint-*.sh` на review gate |
| M9 | **Frontmatter config** | declarative | `model:`, `allowed-tools:`, `description:` |

**Hard** — нельзя обойти. **Soft** — агент следует потому что так написано в prompt.

### Карта ключевых правил → mechanisms → фаза

| Правило | Источник | Mechanisms | Phase |
|---------|----------|-----------|:-:|
| Human gate на каждой стадии (не аутсорсить мышление) | [CRISPY §9, §13](CRISPY.md) | **M1** | **1** |
| Serial execution (один in-progress change) | [MISSIONS §7](MISSIONS.md) | **M1** | **1** |
| State в файлах, не в LLM памяти | [12-FACTOR §6](12-FACTOR.md) | **M1** | **1** |
| ≤40 инструкций на агента | [CRISPY §1](CRISPY.md) | **M8** (instruction counter — static, на CI) | **2** |
| Sub-agent возвращает `file:line`, ≤30 строк | [NO-VIBES §6](NO-VIBES.md) | **M8** (generic line-count) — потом M3+M6+M7 в Phase 3 | **2** |
| Research = только факты, без opinion-words | [CRISPY §3](CRISPY.md) | **M8** (`opinion-words.sh` grep `recommend\|should\|better`) — потом M6+M7 в Phase 3 | **2** |
| Design discussion ≤220 строк | [CRISPY §4](CRISPY.md) | **M8** (generic line-count) — потом M6 в Phase 4 | **2** |
| Structure outline ≤100 строк, vertical | [CRISPY §5, §6](CRISPY.md) | **M8** (line-count + horizontal-pattern lint) — потом M6 в Phase 5 | **2** |
| Compact errors — PASS/FAIL + первые 20 строк | [12-FACTOR §7](12-FACTOR.md), [NO-VIBES §8 анти](NO-VIBES.md) | **M4** (`build-check.sh`/`test-check.sh`) — wrapper, потом M2 (gradle direct запрещён) в Phase 6 | **2** |
| Trajectory protection (>2 ошибки подряд = новый контекст) | [NO-VIBES §4](NO-VIBES.md) | **M5** (PostToolUse counter в `handoff.md`) | **2** |
| Questions/research БЕЗ знания задачи | [CRISPY §3](CRISPY.md) | **M2** (researcher не читает `proposal.md`) + M3 + M6 + M7 + M8 (\*reuse Phase 2\*) | 3 |
| Не читать whole files | [NO-VIBES](NO-VIBES.md) anti | M7 (skill учит Grep/Read с offset) | 3+ |
| Validation Contract до кода | [MISSIONS §4](MISSIONS.md) | **M1** (design не → completed без VC файла) | 4 |
| Plan со снипетами до/после, ≤7 шагов | [CRISPY §7](CRISPY.md) | M6 + **M8** (schema validation) | 6 |
| Structured handoffs (Missions schema) | [MISSIONS §6](MISSIONS.md) | M6 + **M8** (schema validation на stage completion) | 6 |
| Read code, not plan | [CRISPY §9](CRISPY.md) | UX flow в `/workflow`: diff перед approve | 6-7 |
| Adversarial verifier (без design/plan) | [MISSIONS §5](MISSIONS.md) | **M2** (`allowed-tools:` без `design.md`/`plan.md`) | 7 |
| Model per role (droid whispering) | [MISSIONS §9](MISSIONS.md) | **M9** (`model:` frontmatter) | 10 |

**Жирным** — hard enforcement (структурно невозможно обойти).

### Что фреймворк НЕ enforce'ит (sentinel: discipline + Claude Code built-ins)

| Правило | Источник | Почему не enforce | Замена |
|---|---|---|---|
| Smart Zone (≤35% context fill для новичков, ≤60% experienced) | [NO-VIBES §5](NO-VIBES.md), [CRISPY Q&A](CRISPY.md) | Real token count недоступен mid-session; порог fuzzy (Dex сам ходит до 60%); эвристика char-count врёт на 20-30%; Goodhart's law. | Claude Code's built-in `/context` + привычка |
| «Wrap up при degradation» | [NO-VIBES §1, §4](NO-VIBES.md) | Qualitative («I apologize for the confusion» паттерн), не сводится к числу | Engineer's judgement — framework не блокирует |
| Compaction infra | [CRISPY §11](CRISPY.md) — явно retract | Artifacts per stage = resume точки, compaction не нужна | — |

### Worked example: research isolation

Правило ([NO-VIBES §6](NO-VIBES.md), [CRISPY §3](CRISPY.md)): research stage возвращает факты в формате `file:line — что там`, ≤30 строк, без opinion'ов, **без знания задачи**.

В framework'е enforce'им **пятью механизмами одновременно:**

1. **M2 (tool restrictions):** researcher агент имеет `allowed-tools: Read(.foundry/changes/*/questions.md), Read(src/**), Grep, Glob`. **Не имеет права читать `proposal.md`** — это hard enforcement через Claude Code.
2. **M3 (sub-agent isolation):** researcher делегирует чтение кодебазы research sub-agent'у через Task tool — свежий контекст. Sub-agent тоже без `proposal.md`.
3. **M6 (agent prompt):** `agents/researcher.md` явно специфицирует output format и запрещённые слова.
4. **M7 (skill):** `skills/workflow/research-contract/SKILL.md` — детальный контракт + анти-паттерны.
5. **M8 (validation):** `scripts/lint-research.sh` грепает на `recommend|should|better|следует|рекомендую`, считает строки. Запускается перед approve gate — `tracking.sh` отказывается выполнить `set-stage research completed` если lint fail.

Один принцип = пять слоёв, работающих вместе. **Это и есть "framework enforce'ит доктрину".** Если убрать любой слой — discipline ослабевает (агент может проигнорировать prompt, но не может обойти M2 + M8).

---

## Pipeline (target shape — детализируется по фазам)

CRISPY 8 фаз + verify из Missions:

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
| 9 | pr | bash + template | no | Final approve |

[CRISPY §12](CRISPY.md) — phase'ы; [MISSIONS §5](MISSIONS.md) — adversarial verifier.

---

## Phase 0 — Plugin skeleton

**Цель:** валидный пустой marketplace plugin, устанавливается локально без ошибок.

### Deliverable

- `.claude-plugin/plugin.json` — минимальный manifest
- `.claude-plugin/marketplace.json` — минимальный marketplace descriptor
- Пустые директории: `agents/`, `skills/`, `commands/`, `scripts/`, `hooks/` (с `.gitkeep`)
- `hooks/hooks.json` — пустой skeleton (без хуков пока)
- `README.md` — одна параграф «что это»

### Структура корня после Phase 0

```
foundry/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── agents/.gitkeep
├── skills/.gitkeep
├── commands/.gitkeep
├── scripts/.gitkeep
├── hooks/
│   └── hooks.json
├── 12-FACTOR.md
├── CRISPY.md
├── MISSIONS.md
├── NO-VIBES.md
├── README.md
└── ROADMAP.md
```

### Проверки

- [ ] `claude plugin validate ./` проходит без ошибок
- [ ] Локальная установка чистая (`claude plugin install ./` или эквивалент)
- [ ] `/context` в фреш-сессии показывает overhead плагина ≤200 токенов
- [ ] `git status` чистый после установки

### STOP

Не идём в Phase 1, пока пустой плагин не ставится чисто и не валидируется.

---

## Phase 1 — Change lifecycle framework (no LLM)

**Цель:** управлять change'ами полностью без LLM-вызовов. Это substrate + **первый слой enforcement (M1)**, на котором живут все последующие фазы.

**Enforcement-вклад фазы:** M1 (state machine) — hard enforcement для:
- Human gate как обязательный transition (агент не может сам пометить стадию `completed`)
- Serial execution (один in-progress change за раз)
- Невозможность обратных transitions (`done` → `backlog` запрещён)
- Stage state machine (нельзя `completed` без артефакта, проверяется в Phase 4+ когда появятся артефакты)

### Концепция

Каждый **change** — единица работы, проходящая через стадии CRISPY pipeline.

**Два уровня состояния:**

1. **Bucket state** (положение в файловой системе):
   - `backlog` — создан, не начат
   - `in-progress` — активная работа
   - `done` — завершён
   - `declined` — отклонён с причиной

2. **Stage state** (per стадия в `tracking.yaml`):
   - `required` — стадия обязательна
   - `skipped` — стадия пропущена
   - `active` — стадия в работе
   - `completed` — артефакт стадии готов и approved

Phase 1 **не коммитит** конкретный список стадий — он приходит позже (Phase 2+ добавляет questions/research, Phase 3 добавляет design, etc.). `tracking.yaml` хранит список стадий как массив, framework агностичен к именам.

### Файловая раскладка в target проекте

```
.foundry/
├── changes/
│   ├── backlog/
│   │   └── <slug>/
│   │       ├── tracking.yaml
│   │       └── proposal.md
│   ├── in-progress/
│   ├── done/
│   ├── declined/
│   └── .template/
│       ├── tracking.yaml
│       └── proposal.md
```

Артефакты стадий (`questions.md`, `research.md` и т.д.) добавятся в директорию change'а в Phase 2+.

### Схема `tracking.yaml`

```yaml
slug: add-rate-limiting
title: Rate limiting for /api/orders
created_at: 2026-05-24T10:00:00Z
updated_at: 2026-05-24T10:00:00Z
status: backlog
stages: []   # пустой массив — стадии добавляются Phase 2+
history:
  - at: 2026-05-24T10:00:00Z
    actor: user
    event: created
```

Когда Phase 2 добавит первую стадию, `stages:` пополнится:
```yaml
stages:
  - name: questions
    state: todo
```

### Deliverable

**Bash скрипты** (`scripts/`):
- `change.sh` — CRUD по change'ам: `new`, `locate`, `move`, `list`
- `tracking.sh` — read/write `tracking.yaml`: `get-bucket`, `set-bucket`, `add-stage`, `set-stage`, `append-history`
- `state-machine.sh` — валидация переходов bucket'ов и stage state'ов

**Команды** (`commands/`):
- `change.md` — `/change` (browse + drill + state mutations через AskUserQuestion)
- `setup.md` — `/foundry:setup` (скаффолд `.foundry/` в целевом проекте)

**Skills** (`skills/`):
- `workflow/lifecycle/SKILL.md` — state machine reference, schema YAML
- `workflow/conventions/SKILL.md` — раскладка `.foundry/`, naming, slug rules

**Template** (внутри `commands/setup.md` создаёт):
- `.foundry/changes/.template/tracking.yaml`
- `.foundry/changes/.template/propose.md`
- `.foundry/changes/{backlog,in-progress,done,declined}/.gitkeep`

### Проверки (exercise на реальных change'ах)

- [ ] `/foundry:setup` в пустом проекте создаёт `.foundry/` структуру
- [ ] `/change "rate limit for orders"` создаёт change в `backlog/` с tracking.yaml и propose.md
- [ ] Создать 3 change'а с разными slug'ами
- [ ] Переместить один: `backlog → in-progress` (через `/change` drill + AskUserQuestion)
- [ ] Переместить один в `declined` с причиной — поле `decline_reason` в YAML
- [ ] `tracking.sh` отказывается выполнить invalid transition (`done → backlog`)
- [ ] `/change` (без аргументов) показывает таблицу всех change'ей с их bucket'ом
- [ ] `history:` в YAML корректно накапливается на каждой мутации

### Применяемые принципы

- [12-FACTOR §5](12-FACTOR.md) — все state transitions через bash, не через LLM
- [12-FACTOR §6](12-FACTOR.md) — state в файлах, любая команда может прочитать актуальное
- [NO-VIBES §8](NO-VIBES.md) — не используем слово "spec" в именах артефактов (propose, change — нейтральные)

### STOP

Не идём в Phase 2, пока:
1. На реальном проекте можно создать-провести-завершить change без LLM
2. State machine ловит invalid transitions
3. `/change` drill UX работает (можно из него мутировать состояние)

Это базовый каркас. Без него LLM-стадии бессмысленны — они должны куда-то писать артефакты и обновлять state.

---

## Phase 2+ — намёткой

Детализируется по мере прохождения. Список даётся чтобы видеть направление, не как commitment:

- **Phase 2** — **M4 + M8 substrate**: generic lint scripts (instruction count, line count, opinion-words, horizontal-pattern) + bash wrappers для build/test (compact errors PASS/FAIL + 20 строк) + trajectory-counter hook. Reusable infra **до** producer-агентов. [CRISPY §1, §3, §4, §5, §7](CRISPY.md), [12-FACTOR §7](12-FACTOR.md), [NO-VIBES §4, §6](NO-VIBES.md). *(Прежний план «Metrics через OTel» drop'нут — runtime token metrics не поддержаны докладами, см. секцию «Что фреймворк НЕ enforce'ит» выше.)*
- **Phase 3** — Stages `questions` + `research`: валидация objectivity-разделения. Plug в Phase 2 lint substrate. [CRISPY §3](CRISPY.md)
- **Phase 4** — Stage `design`: главный leverage point, deep human review. [CRISPY §4](CRISPY.md). Здесь же — Validation Contract init. [MISSIONS §4](MISSIONS.md)
- **Phase 5** — Stage `structure`: vertical outline. [CRISPY §5, §6](CRISPY.md)
- **Phase 6** — Stages `plan` + `worktree` + `implement` (per-task RPI loop). Structured handoffs. [MISSIONS §6](MISSIONS.md)
- **Phase 7** — Stage `verify` (creator-verifier adversarial). [MISSIONS §3, §5](MISSIONS.md)
- **Phase 8** — `/quickfix` bypass для тривиальных задач. [NO-VIBES §14](NO-VIBES.md)
- **Phase 9** — Domain layer: Kotlin/Spring/distributed skills
- **Phase 10** — Marketplace polish + droid whispering (model per role). [MISSIONS §9](MISSIONS.md)

---

## Open questions (фиксируем по мере необходимости)

- Schema YAML — flat или nested `stages:`? (флэт легче парсить awk'ом)
- Slug generation — auto из title (LLM) или ручной (user)?
- `tracking.yaml` history — append-only лог или ротация?
- Multi-change параллелизм — один in-progress за раз или несколько? (для solo, по [MISSIONS §7](MISSIONS.md), serial проще)

Эти вопросы решаются на Phase 1, не сейчас.

---

*Phase N не закрыт, пока на нём не прогнан реальный change. Метрики (с Phase 2) подтверждают success criteria.*
