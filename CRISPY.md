# CRISPY (RPI Update)

> **Источник:** Dexter Horthy, HumanLayer. Talk: «Everything We Got Wrong About Research-Plan-Implement».
> **Дата:** 2026 (после No Vibes Allowed)
> **Контекст:** публичный пересмотр RPI методологии Декса. Часть рекомендаций предыдущего доклада retract'нута. Это **самый свежий канон** Декса по coding agents.

---

## Тезис

RPI работал у экспертов, но не работал у команд — требовал «magic words» в промптах. Real проблемы: (1) единый monolithic prompt с 85+ инструкциями превышал instruction budget, (2) research получал opinions вместо facts когда знал задачу, (3) reading long plans не давало leverage, (4) horizontal plans = 2000 строк кода до первого теста.

Решение — **CRISPY**: 8 фаз, каждая ≤40 инструкций, разделённые контексты для объективности, vertical decomposition, **read the code**.

> «I am humble enough to admit when I was wrong.»

---

## Retracts из No Vibes Allowed

### ⚠️ Retract 1: «Read plans, not code» → «Read the code»

Цитата из No Vibes (sept 2025): tech lead reads plans, скоростно держится в курсе.

Цитата из CRISPY: «Please, please read the code. We tried not reading the code for like six months. It did not end well. We had to rip out and replace large parts of that system.»

Reasoning: 1000-строчный plan ≈ 1000 строк кода. Plans have surprises — план и код расходятся. **Не leverage.**

Q&A: «Six months ago I said not to read it. Everyone who is saying don't read the code now is going to be in six months being like, yeah, we had to throw that out.»

### ⚠️ Retract 2: «Plans до 1000+ строк» → «Don't read long plan files»

Plans остаются tactical doc для агента. **Spot-check** уровень. Deep review теперь на двух уровнях:
- **Design discussion** (~200 строк) — где человек читает внимательно
- **Сам код**

### ⚠️ Retract 3: «3 фазы RPI» → «8 фаз CRISPY»

Research / Plan / Implement → Questions / Research / Design / Structure / Plan / Worktree / Implement / PR.

### ⚠️ Update: Dumb Zone не useful для experienced users

Q&A: «If you've been using AI coding agents for 60 hours a week — Dumb Zone is not a useful concept. I regularly go up to 60%. I also aggressively keep it below 30.»

Для новичков: shoot for <40%, при 60% — wrap up. Зависит от complexity задачи и instruction/information ratio.

---

## §1. Instruction Budget — 150-200 суммарно, ≤40 per prompt

Frontier LLMs consistently follow ~150-200 инструкций (research Kyle, HumanLayer). Plus CLAUDE.md + system prompt + tools + MCP = бюджет.

Один monolithic RPI planning prompt был **85 инструкций**. Plus всё остальное → half-attended, dice-roll выполнение.

> «You have an instruction budget.»

Решение CRISPY: разбить на несколько prompts, каждый <40 инструкций. Если >40 — пересмотри, можно меньше.

---

## §2. The «Magic Words» problem

Workshops с enterprise engineers: «here's the software, but don't forget to say the magic words». Embarrassing.

Magic words были: «work back and forth with me starting with your open questions and outline before writing the plan». Без этого — план писался сразу, без вопросов, без alignment.

> «If you built a tool that requires hours and hours of training and reps to get good results from, go fix the tool.»

Решение: **разделить planning на отдельные phases с собственными prompts** — design discussion, structure outline, plan. Каждый со своим prompt, не нужно «magic words».

---

## §3. Questions / Research — изоляция от ticket для объективности

**Главная инновация CRISPY.**

Проблема: если research-prompt знает задачу — генерирует **opinions** вместо фактов. «Build rate limiting» → research расскажет про подходы к rate limiting, а не как код работает сейчас.

Решение:
- **Context 1 (questions):** видит ticket → генерирует вопросы к кодебазе, объективные, без упоминания решения
- **Context 2 (research):** видит **только questions, НЕ ticket** → отвечает фактами

> «If you tell the model what you're building, then you get opinions.»

Концептуально аналогично query planning в SQL.

---

## §4. Design Discussion — главный leverage point

После research → новый контекст → **design discussion** ~200 строк.

Содержание:
- Current state
- Desired end state
- Patterns to follow (агент дампит что нашёл — ты говоришь «нет, это какой-то crazy engineer что больше тут не работает, делаем by-the-book»)
- Resolved design decisions
- Open questions

Matt PCO термин: «design concept» — shared understanding между человеком и агентом о том что строится и как.

**Goal:** brain surgery на агенте ДО того как он напишет 2000 строк кода.

> «You want to give the agent every single opportunity to show you what it's wrong about before you go write 2,000 lines of code.»

Tradeoff vs 1000-line plan: 200 line design — много opportunities re-steer. Plan тоже остаётся, но он tactical, spot-check.

---

## §5. Structure Outline — vertical phases, как C header file

После design → новый контекст → **structure outline** ~2 страницы.

Если design = «where are we going», structure = «how do we get there».

Архитектурный аналог: design = architecture review meeting, structure = sprint planning meeting.

Содержание:
- Highлевелный обзор фаз
- Порядок изменений
- Как тестируем после каждой фазы

> «If the plan is the implementation, the outline is the C header files. Just the signatures and the new types.»

Достаточно чтобы увидеть **что агент думает** и поправить если wrong — без чтения 1000-строчного плана.

---

## §6. Vertical plans, NOT horizontal

Несмотря на промптинг и eval'ы, модели **любят horizontal plans**:
1. Сделаем всю БД
2. Потом весь service layer
3. Потом весь API
4. Потом весь frontend
→ 2200 строк кода → не работает → непонятно где сломано (ни модель не проверяла по дороге, ни ты).

**Vertical plan:**
1. Mock API endpoint + работающий frontend
2. Wire frontend to mock
3. Service layer работает
4. DB migration
5. Все вместе

Same amount of code, но **checkpoints**: видишь работает или нет, паузишь и фиксишь.

> «I want to make sure each two, three, 400 line block is correct.»

---

## §7. Plan — tactical doc for the agent (spot-check)

Plan остаётся. Building на artifact'ах (research + design + structure) → создаём plan со снипетами кода. Это `create_plan` prompt, тот же шаблон что раньше.

**Но:** теперь это **for the agent**, не для глубокого human review. Уже alignment'нулись на design discussion. Plan spot-check'аем, deep review — кода.

> «We've already done enough aligning that I'm just going to spot check this and then we save the deep review for the actual code.»

---

## §8. Don't use prompts for control flow

Урок из splitting прокачивания: **if-statement is really powerful. LLMs are really good at classifying.**

Использовать prompts для control flow («if complaint → do X, if billing → do Y» в одном prompt) → классифицируешь input → отдаёшь в smaller focused prompts с far fewer instructions и actions.

> «Don't use prompts for control flow if you can use control flow for control flow.»

Применимо не только к coding agents — любой LLM-based pipeline.

---

## §9. Read the code (not the plan)

Бичевая дискуссия в Twitter / SF AI community. Дексова позиция:

> «If you have people who depend on your code, please I'm begging you please read it. We have a profession to uphold.»

Counter-arguments он рассматривает:
- «But Beads has 300k lines and nobody reads» → OSS, никто не платит деньги, разные stakes от production SAS
- «Doesn't scale» → возможно через 6 месяцев изменится; пока reads + 2-3x speedup лучше чем 10x с throw-everything-away через 6 месяцев

Q&A:
> «We're binary searching through the space of how much of the code should you read.»

---

## §10. 2-3x speedup target, not 10x

> «Going 10× faster doesn't matter if you're going to throw it all away in 6 months. Shoot for 2 to 3×.»

«2026 — год no more slop.» Difference между slop и craft. Agent swarms / gas-town подход критикует за невозможность ensure quality на scale.

> «Better business outcomes than going 10× faster and shipping bunch of slop and hoping that GPT-7 will fix it for you.»

---

## §11. Compaction не нужна если static artifacts работают

Q&A: «We don't use the built-in compaction because everything that matters is going into static assets — you can always resume from where you left off without worrying about the quality of an autocompact or manual compact.»

**Значит:** artifact pipeline (questions.md, research.md, design.md...) уже решает то что compaction пыталась решить. Resume точки = stage artifact'ы.

---

## §12. CRISPY pipeline — 8 phases (full)

1. **Questions** — generation вопросов (видит ticket)
2. **Research** — answers, facts only (НЕ видит ticket)
3. **Design** — discussion ~200 строк, deep human read
4. **Structure** — outline ~2 страницы, spot-check
5. **Plan** — tactical, со снипетами, spot-check
6. **Worktree** — git branch (mechanical)
7. **Implement** — execution по плану
8. **PR** — pull request

Spelling: **C**RISPY?

> «It didn't make a very good acronym, so we just picked the ones we liked.»

Acronym не строгий — важна **методология**, не наименование. (Контраст с RPI где acronym стал semantic diffusion victim.)

---

## §13. Что НЕ покрыто в этом докладе

- Implement side — отдельный разговор
- Testing & verifying — «I don't have a good answer, it's a whole other talk» (Drew's talk)
- Как measure impact на eng teams — «we've been trying to measure developer productivity for 50 years, still don't know how»
- Как platform team rollout'ит общие prompts/skills без breaking workflows

> «Three steps was already a lot for some people to learn, and now there are seven.»

---

## Ключевые цитаты

- «I am humble enough to admit when I was wrong.» — на retract'ы
- «If you tell the model what you're building, then you get opinions.» — про questions/research изоляцию
- «You want to give the agent every single opportunity to show you what it's wrong about before you go write 2,000 lines of code.» — про design discussion
- «If you built a tool that requires hours and hours of training and reps, go fix the tool.» — про magic words
- «Please, please read the code.» — самый чёткий retract
- «2026 is supposed to be the year of no more slop.»

---

## Что важно для foundry

CRISPY — **primary канон** foundry.

- **§1 (instruction budget):** каждый producer-агент ≤40 инструкций
- **§3 (questions/research изоляция):** наш `researcher` НЕ получает propose.md, только questions
- **§4 (design discussion):** designer-агент производит ~200 строк, **главный human gate**
- **§5 (structure outline):** outliner-агент, vertical phases
- **§6 (vertical decomposition):** инвариант — каждая фаза имплементации компилируется и тестируется
- **§7 (plan = tactical):** plan со снипетами, но spot-check, не deep review
- **§8 (control flow ≠ prompts):** routing через state machine и bash, не «orchestrator-LLM решает что дальше»
- **§9 (read code):** code review = mandatory gate
- **§11 (no compaction):** не строим compaction infra — artifacts per stage = resume точки
- **§12 (8 phases):** наш pipeline в точности повторяет CRISPY

**Что berём с осторожностью:**
- **§10 (2-3x target):** good framing, но это про team velocity, не про foundry feature
- **§13 (testing):** отдельная зона, дополняем из MISSIONS Validation Contract
