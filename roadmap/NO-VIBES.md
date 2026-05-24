# No Vibes Allowed

> **Источник:** Dex Horthy, HumanLayer. Talk: «No Vibes Allowed: Solving Hard Problems in Complex Codebases».
> **Дата:** осень 2025 (после 12-Factor, до CRISPY)
> **Контекст:** доклад про context engineering для coding agents. Применение принципов 12-Factor к Cloud Code / coding agent workflow.
> **⚠️ Важно:** часть рекомендаций этого доклада была публично пересмотрена Дексом в [CRISPY.md](CRISPY.md) — отмечено ⚠️ ниже.

---

## Тезис

Coding agents работают плохо в brownfield кодебазах и на complex tasks (Eigor data: shipping +50% но половина — rework slop). Решение — **context engineering**: агрессивно управлять context window, держать в Smart Zone, использовать sub-agents для изоляции. Цель: **2-3× throughput с no slop**.

> «It was a team of three. It took eight weeks. It was really freaking hard. But now that we solved it, we're we're never going back.»

---

## §1. Naive → smart progression

Naive: «попроси, скажи где не так, повторяй пока не сдашься или контекст не кончится».

Smart: при первом признаке плохой траектории — **новый контекст**. Тот же prompt, та же task, но «не туда не ходим, там не работает».

Когда время старта заново: когда видишь «I apologize for the confusion» — это маркер испорченного контекста.

---

## §2. Intentional compaction

Регулярно (не дожидаясь поломки): взять текущий context window, попросить агента **сжать в markdown файл**. Можно review'нуть, тегнуть. Новый агент стартует с этим — сразу к делу, без re-searching и re-understanding codebase.

Что компактим: looking for files, code flow understanding, file edits, test/build output. Особенно важно при наличии MCPs дампящих JSON с UUIDs.

**Формат правильной компакции:** точные файлы и номера строк, релевантные проблеме.

---

## §3. LLMs are stateless (но не pure functions — nondeterministic)

Единственный способ получить better tokens out — better tokens in. Каждый turn loop'а Claude выбирает next tool из сотен правильных и сотен неправильных. **Только context влияет на выбор.**

Оптимизируем context для (в порядке приоритета):
1. **Correctness** — правильная информация
2. **Completeness** — все нужное там
3. **Size** — нет лишнего
4. **Trajectory** — паттерны разговора

---

## §4. Trajectory matters (буквально, не метафора)

Pattern «я ошибся → human yelled → я ошибся → human yelled» → модель видит паттерн → next-most-likely token: «better do something wrong so the human can yell again».

Это не метафора — это буквально как работает next-token prediction.

**Worst things в context (ranked):**
1. **Incorrect information** — самое плохое
2. **Missing information** — плохо
3. **Too much noise** — тоже плохо но менее

---

## §5. Dumb Zone (~40% context fill)

168k токенов окно Claude Code. Около **40% fill** начинается degrading. Yes, можно ехать на 60% и получать good-enough для своей задачи. Но **меньше окна используешь — лучше results**.

> «The less of the context window you use, the better results you will get.» — Jeff Huntley

MCP servers — частая причина: dump'ят инструкции про инструменты которые тебе не нужны → contextoknow забит до начала работы → плохое instruction following при кодинге.

**⚠️ Обновление в CRISPY Q&A:** для experienced users (60+ часов/неделю с агентами) Dumb Zone — не useful концепт. Регулярно ходит до 60%. Новичкам: shoot for <40%, при 60% — wrap it up.

---

## §6. Sub-agents — для изоляции контекста, НЕ для ролей

**Антипаттерн:** frontend-agent + backend-agent + QA-agent + data-scientist-agent.

> «Please stop. Sub agents are not for anthropomorphizing roles. They are for controlling context.»

**Паттерн:** parent делегирует «найди как это работает» → sub-agent в новом контексте → читает / ищет / понимает → возвращает **очень короткое сообщение** «нужный файл здесь». Parent читает один файл, дальше работа.

---

## §7. Frequent Intentional Compaction (RPI workflow)

Layer поверх sub-agents. Цель — всегда в Smart Zone. Три фазы:

1. **Research** — понять как система работает, найти правильные файлы, объективно (без opinion'ов)
2. **Plan** — точные шаги, имена файлов, code snippets, явные тесты после каждого изменения
3. **Implement** — пройти plan, держа контекст низким

**⚠️ ОБНОВЛЕНО в CRISPY:** RPI разделён на 8 фаз (questions/research/design/structure/plan/worktree/implement/PR). Каждый prompt ≤40 инструкций.

---

## §8. Specri dev сломан (semantic diffusion)

> «Specri development is broken. Not the idea, but the phrase.»

Martin Fowler 2006: «There will never be a year of agents because of semantic diffusion.» Хороший термин → 100 людей понимают по-разному → бесполезно.

Что люди называют «spec»:
- Better prompt / PRD
- Verifiable feedback loops + back pressure
- Treating code like assembly (Sean Grove style)
- Set of markdown файлов while coding
- Documentation for OSS library

«Spec → useless now. Semantically diffused.» Использовать само слово опасно — каждый поймёт по-своему.

---

## §9. Onboarding agents — progressive disclosure, NOT preloaded

**Антипаттерн:** один большой CLAUDE.md в корне с whole context. На больших кодебазах либо слишком длинный (агент исчерпывает Smart Zone на чтении доки), либо incomplete.

**Лучше:** shard down stack — CLAUDE.md в каждой папке с своей спецификой. Pull в context только релевантное.

**Ещё лучше — on-demand compressed context:** дать steering «работаем в этой части кодебазы» → research prompt / skill запускает sub-agents через vertical slices → строит research document — snapshot основанный **на самом коде**.

**Почему не preloaded docs:** документация всегда отстаёт от кода. Между actual code, function names, comments, documentation — **maximum lies in documentation**.

> «You could make it part of your process to update this, but you probably shouldn't because you probably won't.»

---

## §10. Mental alignment — это и есть смысл code review

«Что такое code review?» → «Mental alignment.»

Не просто проверка корректности — **как держать команду на одной странице** относительно того как кодебаза меняется и почему.

Tech lead физически не может читать 1000 строк Go в неделю при росте скорости. **Но может читать планы** — этого достаточно чтобы catch'ить проблемы рано и понимать эволюцию системы.

**⚠️ РЕТРАКТНУТО в CRISPY:** «I was wrong. Please read the code. Don't read long plan files.» Теперь leverage point — design discussion (200 строк), не plan (1000 строк).

---

## §11. AMP threads на PR

Mitchell-pattern: на pull request не просто diff (стена green text в GitHub), а:
- Точные шаги
- Промпты
- Hey, ran the build at end and it passed

Takes the reviewer на journey которое simple GitHub PR can't.

---

## §12. Plans с реальными code snippets

Goal: leverage. Хочешь high confidence что model сделает right thing. Plan без сниппетов = непонятно что произойдёт.

> «We've over time iterated towards our plans include actual code snippets of what's going to change.»

Trade-off: длиннее plan → выше reliability → ниже readability. **Sweet spot есть для каждой команды/кодебазы.**

**⚠️ ОБНОВЛЕНО в CRISPY:** plans остаются tactical с снипетами, но плэны >1000 строк теперь анти-паттерн. Plan — для агента (spot-check). Deep review — design discussion + сам код.

---

## §13. Don't outsource the thinking

> «AI cannot replace thinking. It can only amplify the thinking you have done or the lack of thinking you have done.»

«No magic prompt.» Не сработает если не прочитаешь plan. Process должен быть построен вокруг того что **ты, builder, в back-and-forth с агентом, читая планы по мере создания**.

> «A bad line of research like misunderstanding of how the system works → your whole thing is going to be hosed.»

Const move human effort и focus на **highest-leverage parts of pipeline**.

---

## §14. Scale complexity to task

Не каждой задаче нужен full RPI:
- Change button color → just talk to agent
- Simple bug → /research + /impl
- Small feature one file → /research + /plan + /impl
- Multi-repo medium feature → full RPI
- Architecture change → full RPI + extra review

> «The hardest problem you can solve, the ceiling goes up the more context engineering compaction you're willing to do.»

---

## §15. Pick one tool, get reps

> «I recommend against minmaxing across Claude and Codex and all these different tools.»

Reps дают intuition сколько context engineering применять. Будешь ошибаться (too big, too small) — это normal. Переключение между tools = потеря накопленных patterns.

---

## §16. Cultural change is hard, top-down only

> «Senior engineers hate it more and more every week because they're cleaning up slop that was shipped by Cursor the week before.»

Это не вина AI. Не вина mid-level engineer. **Adoption должен идти сверху.** Если tech lead не использует — команда не выстроит правильный процесс.

> «Pick one tool and get some reps.»

---

## §17. Harness engineering ≠ specri dev

Если хочется hypy слова — это **harness engineering**, часть context engineering. Как ты интегрируешься с integration points (Codex/Claude/Cursor), как customize codebase. **Не silver bullet, no perfect prompt.**

---

## Ключевые цитаты

- «Most production agents weren't that agentic at all. They were mostly just software.» — про что вообще доклад
- «Sub agents are not for anthropomorphizing roles. They are for controlling context.»
- «AI cannot replace thinking. It can only amplify the thinking you have done.»
- «A bad line of research is a hundred bad lines of code.»

---

## Что важно для foundry

- **§5 (Dumb Zone):** инвариант ≤35% per стадия. Метрики через OTel real tokens, не heuristic.
- **§6 (sub-agents для изоляции):** наш researcher — единственный sub-agent, контракт «факты, ≤30 строк».
- **§4 (trajectory):** при второй ошибке implementor'а — новый контекст, явно в handoff.md.
- **§9 (on-demand context):** не строим self-updating CLAUDE.md, доки врут.
- **§8 (specri dev broken):** не используем слово «spec» в именах артефактов. Используем дексов канон: research / design / structure / plan.
- **§13 (don't outsource thinking):** user gate на каждой стадии.
- **§14 (scale complexity):** `/quickfix` команда для тривиальных задач.

**Применяем с обновлениями из CRISPY:**
- §7 (RPI 3 фазы) → CRISPY 8 фаз
- §10 (читай планы) → читай код, deep review на design discussion
- §12 (plans со снипетами) → plans остаются tactical, но не должны быть >1000 строк
