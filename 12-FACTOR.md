# 12-Factor Agents

> **Источник:** Dex Horthy, HumanLayer. AI Engineer 2025 (June). Talk: «12-Factor Agents: Patterns of reliable LLM applications».
> **Дата:** июнь 2025 (предшественник No Vibes Allowed)
> **GitHub:** github.com/humanlayer/12-factor-agents

---

## Тезис

Большинство production-агентов **на самом деле не agentic** — это в основном software с вкраплениями LLM. Надёжность достигается не magic'ом фреймворка, а применением классических принципов software engineering к LLM-based приложениям. Heroku когда-то определил «cloud native» — этот доклад претендует на ту же роль для AI agents.

> «Most production agents weren't that agentic at all. They were mostly just software.»

---

## §1. JSON extraction — самая магическая возможность LLM

Не tool use, не loops, не RAG. Превращение **предложения в JSON-структуру** — фундамент всего остального. Что ты делаешь с JSON дальше — отдельный вопрос (см. §4).

> «It is turning a sentence like this into JSON that looks like this. Doesn't even matter what you do with that JSON.»

---

## §2. Own your prompts

Готовые абстракции дают «banger prompt» который не написал бы за 3 месяца promt-school. Но за определённым quality bar **придётся писать каждый токен вручную**.

LLM — pure focus functions: качество tokens out определяется тем какие tokens in.

> «If you want to get past some quality bar, you're going to end up writing every single token by hand.»

---

## §3. Own your context window

OpenAI messages format — это default, не закон. Можно строить контекст как угодно: одно user-сообщение со всей историей, кастомный формат event/state, что угодно. Главное — **смотреть на каждый токен**, оптимизировать density и clarity.

Context engineering = вся работа над тем как правильные токены попадают в модель: prompt + memory + RAG + history.

---

## §4. Tools «harmful» — нет ничего магического в tool use

Аналогия с «GOTO considered harmful» (Dijkstra). Tool use это **не** ethereal alien interacting with environment. Это:
1. LLM выдаёт JSON
2. Детерминированный код что-то с ним делает
3. Опционально — результат обратно в контекст

Структуры → switch statement / loop. Никакой магии.

> «There's nothing special about tools. It's just JSON and code.»

---

## §5. Own your control flow

Code is a graph (любой `if` — directed graph). Naive agent loop:

```
event → prompt → tool call → result on context → repeat → final answer
```

Не работает на длинных workflow'ах — context window растёт, качество падает.

Что работает: **own the inner loop**. Тогда можешь делать break, switch, summarize, LLM-as-judge — что хочешь. Это даёт flexibility.

Агент = prompt (как выбрать следующий шаг) + switch (что делать с JSON) + builder контекста + loop с условием выхода.

---

## §6. Manage execution state + business state, pause/resume

Любой DAG orchestrator имеет: current step, next step, retry count. Плюс твоя бизнес-логика: messages, displayed data, approval queue.

Хочется launch / pause / resume как у обычных API. Решение:
1. Агент за REST/MCP endpoint
2. Long-running tool call → serialize context window в БД
3. Callback приходит с state ID + result
4. Load state, append result, → обратно в LLM
5. Агент не знает что что-то происходило в background

> «Agents are just software, so let's build software.»

---

## §7. Compact errors in context

Когда LLM зовёт API неправильно или API down — кладёшь ошибку в контекст и пробуешь снова. Опасность: спираль (видели как агент crazy spin out теряя контекст?).

**Не клади blindly:** если после errors пришёл valid tool call — почисть pending errors. Не клади весь stack trace. Suммаризуй. Реши **что именно хочешь сказать модели** чтобы получить лучший результат.

---

## §8. Contact humans with tools (natural language token)

Антипаттерн: модель решает «tool call или message to human» сразу на первом sampling токене.

Правильно: пуш этого решения в natural language token. Модель может вернуть:
- "I'm done"
- "I need clarification"
- "I need to talk to a manager"

Это (1) даёт модели разные пути, (2) переносит intent на токен который модель уже хорошо понимает.

Позволяет строить outer-loop агентов (запускаются по событию, останавливаются на human input).

---

## §9. Trigger from anywhere — meet users where they are

Людям не нужны 7 вкладок ChatGPT-style чатов. Дай агенту email, slack, discord, SMS interface.

> «Just let people email with the agents you're building.»

---

## §10. Small focused agents (micro-agents)

Не «full fat agent» (tools в loop пока не закончит). А **mostly deterministic DAG** с маленькими agent loops по 3-10 шагов.

HumanLayer пример (deployment bot):
- CI/CD detected merged PR → deterministic
- Tests passing → отправка модели «get this deployed»
- Модель: «deploy frontend» (JSON) → human review → «no, backend first»
- Backend approved → deploy → agent: «теперь frontend»
- Готово → обратно в deterministic (e2e tests против prod)
- Fail → rollback agent (тоже маленький)

> «100 tools, 20 steps, easy. Manageable context, clear responsibilities.»

Со временем модели смогут больше → постепенно «увеличиваешь долю LLM» в этой картинке. Но всё ещё хочешь знать как engineer'ить эти штуки для quality.

---

## §11. Find the bleeding edge

Найди задачу **на грани надёжной работы модели** — модель не может сделать right all the time. Если умеешь **инженерить надёжность вокруг этого** — построил что-то magical, лучше чем у остальных.

> «If you can figure out how to get it right reliably anyways because you've engineered reliability into your system — you've created something better than what everybody else is building.»

---

## §12. Stateless reducers (transducers)

Агенты должны быть stateless. State — на тебе, manage как хочешь.

---

## Антипаттерны (явно перечислены)

- **Не каждая задача нужна агент.** Личная история Декса: DevOps agent с make-командами. 2 часа prompt engineering vs 90-секундный bash script. Часто bash побеждает.
- **Wrapper-фреймворки.** Не нужен bootstrap-like wrapper над внутренней магией. Нужен shad/cn-like: scaffolded out, **владеешь кодом**.
- **Скрытие AI-сложности.** Фреймворки часто прячут hard AI parts чтобы «drop in and go». Должно быть наоборот: tools должны убирать другие hard parts чтобы ты фокусировался на AI parts (prompts, flow, tokens).

---

## Ключевые цитаты

- «Agents are software. Anyone ever written a switch statement before?»
- «LMs are stateless functions. Put the right things in context, get the best results.»
- «Find ways to do things better than everybody else by really curating what you put in the model.»
- «AI tech agents are better with people.» (про human-in-the-loop)
- «There are hard things in building agents, but you should probably do them anyways.»

---

## Что важно для foundry

- **§1 (JSON extraction):** Claude Code и так это даёт через tool use — для нас фундамент, не отдельная техника.
- **§2, §3 (own prompts/context):** мы пишем каждый агентский prompt вручную, не используем generators.
- **§5 (own control flow):** state machine на bash, не «промпт решает что дальше».
- **§7 (compact errors):** `build-check.sh` возвращает PASS или FAIL+первые 20 строк — не полный gradle output.
- **§10 (micro-agents):** наши producer-агенты ≤40 инструкций каждый, см. CRISPY.
- **§11 (bleeding edge):** наш фокус — Kotlin/Spring brownfield задачи на грани надёжной автогенерации.
- **§6 (pause/resume):** state в файлах = можно прервать сессию, восстановить в новой.

Что **не берём для v1.0:**
- §8 (contact humans tool) — Claude Code AskUserQuestion это уже даёт
- §9 (trigger from anywhere) — Claude Code это единственный channel
