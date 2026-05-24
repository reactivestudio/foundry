# Missions

> **Источник:** Luke Alvoeiro, Factory. Talk: «The Multi-Agent Architecture That Actually Ships».
> **Дата:** 2026
> **Контекст:** Factory's mission — bring autonomy to entire SDLC. Luke ведёт core agent harness. Раньше — Block / Goose (donated to Agentic AI Foundation).
> **Парадигма:** **Multi-agent ecosystem с multi-day runs.** Отличается от CRISPY (single-context pipeline). Применяется для разных user case'ов.

---

## Тезис

Bottleneck в software engineering — **не intelligence, а human attention**. Engineer может только сопровождать пару задач параллельно, даже если backlog 50. Решение — система которая после human-approved plan **работает часами/днями** автономно, человек возвращается к готовой работе.

> «What if a human decides what to build and then a system figures out how to do so.»

Самая длинная mission в production — **16 дней**, верят что 30 возможно.

---

## §1. Taxonomy multi-agent strategies (5 штук)

Поле — messy: каждый framework со своей терминологией. Luke предлагает таксономию:

1. **Delegation** — parent agent spawn'ит child, получает response. Простейшая, sub-agents в coding tools — пример.
2. **Creator-verifier** — separation of concerns. Implementer biased (cost bias, хочет чтобы код работал). Fresh agent с fresh context — way more likely найти issues. Это почему у нас code review.
3. **Direct communication** — agents DMs each other без central coordinator. **Hard to get right** — state fragments across conversations, no single source of truth.
4. **Negotiation** — communication над shared resource (same API, same code area). **Не обязательно adversarial** — best case это **net positive sum trading** (win-win).
5. **Broadcast** — one to many. Status updates, shared constraints, новый context для всех. Less flashy но critical для coherence на long-running.

---

## §2. Missions = композиция 4 strategies

Missions комбинируют: **delegation + creator-verifier + broadcast + negotiation**.

User flow:
1. Describe goal
2. Scope через conversation
3. Approve plan
4. System runs execution часами/днями
5. Focus на чём-то другом

> «A mission is not a single agent session. It's an ecosystem of agents that communicate through structured handoffs and shared state.»

---

## §3. Three-role architecture

### Orchestrator — planning
Когда описываешь что хочешь, orchestrator работает как **sounding board**:
- Strategic questions
- Identifies unclear requirements
- Produces plan: features + milestones + **validation contract**

### Workers — implementation
Когда feature assigned worker'у:
- Clean context, no accumulated baggage, no degraded attention
- Reads spec
- Implements feature
- Commits via git → следующий worker наследует **working code base + clean slate**

### Validators — verification
Most systems валидируют lint / type-check / tests / code review.

Missions делает ещё **behavior validation**:
- Не «does code look right?»
- А «does this work end-to-end?»

Это позволяет mission'у идти **many hours/days без drifting**.

---

## §4. Validation Contract — killer concept

**Главный артефакт missions.**

Проблема: typical pattern — agent пишет код, пишет тесты, тесты pass, full coverage. **Но тесты shape'ed by code, not by what code was attempting to do.** Tests written after implementation **confirm decisions, not catch bugs**. → System drifts.

Решение: Validation Contract **written during planning, BEFORE any code**.
- Defines correctness **independently of implementation**
- Complex projects: **hundreds of assertions**
- Each feature assigned 1+ assertions it must satisfy
- Sum of all features → every assertion covered

---

## §5. Two validator types

### Scrutiny validator
Traditional + dedicated code review agents:
- Test suite
- Type checking
- Lints
- Spawns code review agent **per completed feature** в milestone

### User Testing validator
Acts like a QA engineer:
- Spawns the application
- Computer use / similar
- Fills out forms
- Checks pages render
- Clicks buttons
- Ensures functional flows holistically

Этот шаг **significantly longer** — interacting с live application. Most of mission's wall clock time здесь, не на token generation.

### Adversarial by design
> «Critically neither validator has seen the code before. They're not invested in the implementation.»

---

## §6. Structured handoffs — self-healing mechanism

Когда worker finishes feature — не просто «I'm done». Заполняет structured handoff:
1. **What was completed**
2. **What was left undone**
3. **Commands run** throughout the loop
4. **Exit codes** of those commands
5. **Issues discovered**
6. **Procedures abided** (что orchestrator определил для worker'а)

Это catch'ит issues, mission self-heals:
- Errors caught at milestone boundaries
- Corrective work scoped
- Mission pulls itself back on track

> «Not by hoping that agents remember what happened but by forcing them to write it down.»

---

## §7. Serial execution — counter-intuitive insight

Obvious choice: parallelism. 10 agents → 10× throughput. **Tried it. Doesn't work для software dev:**
- Agents conflict
- Step on each other's changes
- Duplicate work
- Inconsistent architectural decisions
- Coordination overhead eats speed gains, burning tokens

**Missions: serial execution.** Only one worker OR validator running at any time.

**Внутри feature:** parallelization для **read-only operations** (codebase search, API research). Внутри validator'а — parallel code review.

> «Serial execution with targeted internal parallelization. Seems slower on paper, but error rate drops dramatically.»

Для many-day tasks **correctness compounds**.

---

## §8. Mission Control — UI для async monitoring

Standard chat interface не работает для multi-day workflow. Нужно at-a-glance видеть:
- How much project completed
- What % budget burned

Mission Control dedicated view:
- What is active worker doing right now
- Handoff summaries (что worker/validator discovered)
- Course corrections forward

Run missions **asynchronously**:
- Be plugged in as PM overseeing implementation
- OR just hang out with friends

---

## §9. Droid Whispering — right model in right seat

Everything assumes **using right model for each role**:
- **Planning** — slow careful reasoning
- **Implementation** — fast code fluency + creativity
- **Validation** — precise instruction following

> «No single model nor model provider is best at all three.»

Skill: **droid whispering** — mentally model:
- How different LLMs interact
- Where they fail
- How failures compound over multi-day run
- Deliberate choice какая модель в каком seat

Например: validation — **другой model provider entirely**, чтобы не biased одинаковыми training data.

> «As models continue to specialize, the ability to put the right model in the right seat becomes a compounding advantage.»

Works в обе стороны: structure missions может compensate за модели не на frontier level — validation contracts + milestone checkpoints позволяют running на **open-weight models**.

---

## §10. Bitter Lesson protection

Fear: next model release делает архитектуру obsolete.

Решение: **almost all orchestration logic defined in prompts and skills**, not hard-coded state machine.

- Decomposition of features + failure handling: **~700 lines of text**
- 4 sentences могут dramatically alter execution strategy
- Worker behavior driven by skills orchestrator defines per mission
- Only deterministic logic — very thin, focused на enabling models to do best, system handles bookkeeping

> «Missions ensure the discipline, models provide the intelligence — using primitives they're already familiar with (agents.md, skills).»

---

## §11. Production data (Slack clone example)

- **60% time** на implementation
- **60% tokens** на implementation
- Validation **never succeeds first go** — почти всегда нужны follow-up features → демонстрирует value QA loop
- End result: **50% lines = tests**, **90% code coverage**
- Heavy **prompt caching** чтобы offset цену long-running task

---

## §12. Economics — что unlock'ается

Bottleneck = human attention.

Before missions: team of 5 engineers → maybe 10 work streams concurrent.

С missions: **up to 30 work streams**.

Team focus shifts:
- К architecture, product decisions
- Away from execution worry

Codebase ends up **cleaner than started** — tests, skills, structure от missions делают environment более productive для agents и humans дальше.

---

## §13. Composition map (как 4 strategies реализуются)

- **Delegation** — orchestrator spawns workers + research sub-agents
- **Creator-verifier** — validation и implementation всегда separate agents с separate context
- **Broadcast** — shared mission state, every agent references
- **Negotiation** — milestone boundaries: orchestrator decides «handoff summary correct? need follow-up features? rescope?»

Strategies aren't enough — нужен **connective tissue**:
- Structured handoffs (context preservation)
- Right model per role (droid whispering)
- Architecture improving с model improvement (bitter lesson)

---

## §14. Open questions (Luke называет)

- Как parallelize workload missions для скорости?
- Как orchestrate mission'ы themselves в ещё более complex workflows?

Production data говорит: works at scale today. Try it: Open Droid, `/missions`, argue with orchestrator, approve plan, go do something else.

---

## Ключевые цитаты

- «Bottleneck in software engineering is not intelligence. It's human attention.»
- «Tests written after implementation don't catch bugs. They confirm decisions.»
- «Validation is adversarial by design.»
- «Not by hoping that agents remember what happened but by forcing them to write it down.»
- «Serial execution with targeted internal parallelization.»
- «Missions ensure the discipline, models provide the intelligence.»
- «You're only as strong as your weakest link» (про lock-in в один model provider)

---

## Что важно для foundry — и что НЕ берём

Missions — **другая парадигма** чем CRISPY:
- CRISPY = single-context pipeline + human gates на каждой стадии
- Missions = multi-agent ecosystem + multi-day async + occasional human

Foundry **primary базируется на CRISPY** (solo senior workflow). Из Missions берём только **то что не противоречит CRISPY**:

### Берём:
- **§4 (Validation Contract):** writes ДО кода, lives at change level, evolves через design/structure, проверяется на verify. **Core artifact в foundry.**
- **§5 (creator-verifier adversarial):** наш `verifier` НЕ видит design.md/plan.md — только validation-contract + diff + propose. Fresh context.
- **§6 (structured handoffs):** наш `handoff.md` per task — what done / what undone / commands+exit codes / issues. Self-healing для длинных implementation стадий.
- **§7 (serial execution):** не пытаемся параллелить workers. Одна таска за раз.
- **§9 (droid whispering):** на Phase «polish» — model recommendations per producer-agent (haiku/sonnet/opus).
- **§10 (bitter lesson, частично):** high-level routing — в orchestrator-промпте. Low-level state mutation — в bash. Не строим hard-coded routing state machine для «когда что вызывать».

### НЕ берём (не для solo):
- **§3 (multi-day mission runs):** solo senior держит attention на сессии, не уходит на дни
- **§5 user testing validator (computer use, spawn app, click buttons):** out of scope
- **§8 (Mission Control async dashboard):** Claude Code chat достаточно
- **§4 «hundreds of assertions»:** для solo change обычно 5-20, не сотни
- **§11 (heavy prompt caching):** Claude Code это уже делает under the hood

### Conceptual conflicts с CRISPY (выбираем CRISPY):
- Missions: orchestration в промптах (§10) ↔ CRISPY: control flow в коде (§8 CRISPY). **Resolve:** low-level — код, high-level — orchestrator-промпт.
- Missions: автономный многодневный run ↔ CRISPY: human gate на каждой стадии. **Resolve:** CRISPY-style gates.
