---
name: gof-patterns
description: "Gang of Four (GoF) design patterns for Kotlin/Spring Boot — all 23 classical patterns (5 creational, 7 structural, 11 behavioural) with their Kotlin status: which are subsumed by language features (Singleton = `object`, Strategy = lambda, Observer = `Flow`/Spring events, Composite = sealed hierarchy, Visitor = sealed + exhaustive `when`, Prototype = `data class.copy()`), which still apply with idiomatic Kotlin (Adapter, Bridge, Facade, Abstract Factory, Mediator, Template Method), which Spring provides for you (Proxy via @Transactional/@Cacheable/@Async, Observer via ApplicationEventPublisher, Abstract Factory via @Profile). Use this skill when reading patterns-heavy Java code and translating it to idiomatic Kotlin, recognising a pattern that's already in your codebase but unnamed, naming a design conversation ('this is a Facade'), modernising over-engineered Java-flavoured Kotlin (manual Singleton ceremony, fluent Builder when named arguments would do, classical Visitor), deciding which pattern fits a problem you've already encountered, or auditing whether a 'pattern' someone added actually earns its keep. Trigger especially when somebody writes a Java-style Singleton in Kotlin, hand-rolls a Visitor, builds a fluent Builder when named arguments suffice, manually wires Observer/Observable, asks 'which pattern is this?', or wants to translate a GoF-heavy textbook example into idiomatic Kotlin."
risk: safe
source: "custom — GoF for Kotlin/Spring"
date_added: "2026-05-12"
---

# Gang of Four (GoF) Patterns (Kotlin / Spring Edition)

23 classical design patterns. In Kotlin most are **language features** (Singleton = `object`, Strategy = lambda, Observer = `Flow`/events, Composite = sealed hierarchy, Visitor = sealed + exhaustive `when`) or have **idiomatic shortcuts** that replace ceremony. The remainder still apply, but with less ceremony than the original Java versions.

This skill is the canonical reference for GoF applied through Kotlin idioms and Spring conventions. Sister skills cover the other foundational vocabularies of OO design:

- `solid-principles` — class-level shape rules (one reason to change, open/closed, substitutable, segregated, inverted)
- `grasp-patterns` — responsibility assignment (who should own this method?)

Together: GRASP picks the owner → SOLID validates the shape → GoF names the pattern that emerges.

## Use this skill when

- Translating GoF-heavy Java code into idiomatic Kotlin
- Recognising a pattern in your codebase that's working but unnamed
- A code review surfaces "this is the X pattern" — confirming or correcting the name
- Modernising Java-flavoured Kotlin (manual Singleton, fluent Builder, classical Visitor, hand-rolled Observer/Observable)
- Choosing between several GoF patterns that could solve the same problem
- Deciding which Spring framework feature replaces a hand-coded pattern (`@Transactional` for Proxy, `ApplicationEventPublisher` for Observer)
- Auditing whether a "pattern" someone added actually earns its keep, vs being ceremony

## Do not use this skill when

- The class shape is the question (SRP / OCP / LSP / ISP / DIP) — use `solid-principles`
- The question is *who should own this responsibility* before you've picked a pattern — use `grasp-patterns`
- The task is **language idioms** independent of patterns (data class, scope functions, value class) — see `clean-code-classes`, `clean-code-objects-and-data`
- The task is **architectural layout** (Onion / Clean / Hexagonal) — use `architecture-patterns`
- You're writing routine CRUD with no problem worth naming — patterns are tools, not gates

## Selective Reading Rule

Six resource files. Read the one matching your task — don't load the lot.

| File | What it contains | When to read |
|---|---|---|
| `resources/theory.md` | All 23 GoF patterns (Creational / Structural / Behavioural): intent, the problem each solves, structure, language-agnostic example | First contact with a pattern, refreshing intent, explaining to a teammate, recognising what shape a problem fits |
| `resources/kotlin.md` | Kotlin status per pattern: which language feature replaces it (`object`, `data class.copy()`, sealed + `when`, `by` delegation, function types, `Flow`), idiomatic form when still relevant | Writing or modernising Kotlin; you know the pattern, you want the idiom |
| `resources/spring-boot.md` | Spring-provided patterns: Proxy via AOP, Observer via events, Abstract Factory via `@Profile` / `@ConditionalOnProperty`, Mediator via `@Service`, Strategy via `Map<String, T>` injection | Designing a Spring service; deciding whether to write the pattern or use Spring's built-in |
| `resources/bad-practices.md` | Java-flavoured ceremony in Kotlin: hand-rolled Singleton, fluent Builder when named arguments suffice, classical Visitor, manual Observable/Observer, classical Proxy. Each entry: smell → why it's wrong → idiomatic fix | Code review; pre-merge audit; modernising legacy Kotlin written in Java style |
| `resources/best-practices.md` | When each pattern still earns its keep, the "70% subsumed" rule, communication value of names, the trap of mechanical pattern application, decision rules for picking between patterns | Planning a refactor; framing a design discussion; auditing for over-engineering |
| `resources/cross-references.md` | Bridges to SOLID / GRASP / DDD: Strategy ↔ OCP / Polymorphism, Adapter ↔ Indirection / ACL, Decorator ↔ OCP / `by` delegation, Facade ↔ Pure Fabrication, Observer ↔ Low Coupling / domain events | Mapping a GoF question to a SOLID validation or GRASP responsibility decision; preparing for a design conversation that crosses vocabularies |

## Quick reference — Kotlin status of all 23 patterns

| Category | Pattern | Kotlin status | Verdict |
|---|---|---|---|
| **Creational** | Singleton | `object` keyword | language feature |
| | Builder | named args / `apply` / DSL | mostly unnecessary |
| | Factory Method | companion `create()` | trivial |
| | Abstract Factory | sealed interface + `data object` | useful for families |
| | Prototype | `data class.copy()` | language feature |
| **Structural** | Adapter | wrapper class / extension fn | useful, especially for ACL |
| | Decorator | `by` delegation | language feature |
| | Facade | regular service | unnamed but common |
| | Composite | sealed hierarchy | language feature |
| | Bridge | interface + impl | still applies |
| | Proxy | Spring `@Transactional` / `by` delegation | framework feature |
| | Flyweight | `value class` / interning | rarely needed |
| **Behavioural** | Strategy | function type / lambda | language feature |
| | Observer | `Flow` / Spring events | framework feature |
| | Command | sealed interface | language feature |
| | Iterator | `Iterable` / `Sequence` | language feature |
| | Template Method | abstract class with `final`/`open` | use sparingly |
| | Chain of Responsibility | list + first-match | trivial |
| | State | sealed class + `when` | language feature |
| | Mediator | orchestrator service | regular service |
| | Memento | `data class` snapshot | language feature |
| | Visitor | sealed + exhaustive `when` | **obsolete** — use sealed |
| | Interpreter | type-safe DSL | advanced, rarely needed |

For details on each pattern's intent, Kotlin form, and Spring usage, see the resource files.

## Core meta-rules

1. **70% of GoF is subsumed by Kotlin language features.** Singleton, Strategy, Observer, Composite, Visitor, Prototype, Decorator, Iterator, State, Memento, Command — all are language idioms in Kotlin. The remaining ~30% (Abstract Factory, Bridge, Facade, Mediator, Template Method, Adapter, Interpreter) still apply but with less ceremony than Java versions.
2. **Patterns are diagnostic, not prescriptive.** You don't decide to "use Visitor"; you notice that the shape of the problem fits Visitor (and in Kotlin, that means sealed + `when`).
3. **Don't write Java-flavoured patterns in Kotlin.** Hand-rolled Singleton, fluent Builder when named arguments would do, classical Visitor — these are smells that mark the author hasn't internalised Kotlin's idioms. (See `bad-practices.md`.)
4. **Don't mechanically scan a codebase for "where can I add a GoF pattern?"** That's the source of over-engineered Java enterprise code from the 2000s.
5. **Names are communication, not blueprints.** "This is a Facade" tells your teammate where to look; it doesn't dictate the implementation. Use the names; don't worship them.

## Related skills

- `solid-principles` — class shape rules; many GoF patterns (Strategy, Decorator, Adapter) are SOLID-driven refactors with names
- `grasp-patterns` — responsibility assignment; GRASP picks the owner, GoF names the pattern that emerges
- `clean-code-classes` — class-level Kotlin idioms (`by` delegation, `companion object`, sealed hierarchies)
- `clean-code-objects-and-data` — Tell-Don't-Ask, anaemic-domain anti-pattern (intersects with where Strategy/State live)
- `clean-code-boundaries` — Wrap-Don't-Pass + Anti-Corruption Layer = GoF Adapter at the vendor seam
- `clean-code-systems` — composition root, IoC discipline (where Abstract Factory and Builder live)
- `cqrs-implementation` — sealed `Command` types are the GoF Command pattern
- `messaging-rabbitmq-spring` — distributed Observer pattern via message bus
- `spring-boot-mastery` — Spring's pattern catalogue: Proxy via AOP, Observer via events, Mediator/Facade via `@Service`

## Limitations

- GoF was written for C++/Smalltalk in 1994; the patterns reflect language constraints of that era. Kotlin's language features (sealed, data, value, by, function types, scope functions) collapse most of them.
- Mechanical pattern application produces over-engineered code. The discipline is recognising the shape, not adding the structure.
- Some GoF patterns are obsolete in Kotlin (Visitor especially). Knowing that is part of using GoF correctly.
- For pure functional design (Arrow, structured concurrency), the vocabulary shifts to category theory (functor, applicative, monad). GoF is OO-specific.
