---
name: solid-principles
description: "SOLID principles for Kotlin/Spring Boot — five class-level design rules: Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, Dependency Inversion. What each principle means, the anti-patterns that violate it, idiomatic Kotlin and Spring forms that satisfy it (sealed hierarchies for OCP, constructor injection for DIP, segregated Spring Data interfaces for ISP), refactor recipes, and a PR-review checklist. Use this skill whenever the user designs a class hierarchy, splits a god service, fixes an inheritance smell, segregates a fat interface, replaces concrete-class injection with abstractions, names the design problem in a code review, or audits class shape before merge — even if they do not say 'SOLID' explicitly. Trigger especially when a `when`-chain on type proliferates across files, when a subclass throws `UnsupportedOperationException`, when a service has six unrelated dependencies, when domain code imports `org.springframework.*` or `org.hibernate.*`, when a refactor brief says 'too many reasons to change', or when a code review surfaces 'this class feels off but I can't name it'."
risk: safe
source: "custom — SOLID for Kotlin/Spring"
date_added: "2026-05-12"
---

# SOLID Principles (Kotlin / Spring Edition)

Five class-level design rules. **One reason to change** (S), **open for extension** (O), **substitutable subtypes** (L), **client-shaped interfaces** (I), **depend on abstractions** (D).

In Kotlin, all five remain. The vocabulary is the same; only the idioms shift — sealed classes, `value class`, `by` delegation, scope functions, function types, type variance. In Spring, dependency injection IS DIP, `@RestControllerAdvice` IS OCP, segregated `Repository` interfaces ARE ISP. The framework rewards SOLID; the principles are baked in.

This skill is the canonical reference for SOLID applied through Kotlin idioms and Spring conventions. Sister skills cover the other two foundational vocabularies of OO design:

- `grasp-patterns` — **who** should own a responsibility (the assignment question)
- `gof-patterns` — **what shape** does a recurring collaboration take (the pattern catalogue)

Together: GRASP picks the owner → SOLID validates the class shape → GoF names the pattern that emerges.

## Use this skill when

- A service grew six unrelated dependencies — SRP audit
- A `when (type)` chain repeats across files — OCP refactor with sealed hierarchy
- A subclass throws `UnsupportedOperationException` — LSP violation, split the abstraction
- An implementer stubs half the interface methods — ISP, segregate
- A domain class imports `org.springframework.*` or `org.hibernate.*` — DIP violation, introduce a port
- Code review surfaces "this class feels off" and you need to name the smell
- Pre-merge audit of a new class or hierarchy
- Onboarding a teammate who needs the vocabulary for design conversations

## Do not use this skill when

- You need to assign a responsibility to one of several candidate classes — use `grasp-patterns`
- You're translating Java-flavoured patterns into idiomatic Kotlin — use `gof-patterns`
- The task is **language idioms** (data class, sealed, value class, scope functions) — see `clean-code-classes` and `clean-code-objects-and-data`
- The task is **architectural layout** (Onion / Clean / Layered / DDD) — use `architecture-patterns`
- You're writing a CRUD endpoint with no design problem — these principles are tools, not gates

## Selective Reading Rule

Six resource files. Read the one that matches your task — don't load the lot.

| File | What it contains | When to read |
|---|---|---|
| `resources/theory.md` | The five principles, language-agnostic: definition, intent, "why it matters", canonical example | First contact with SOLID, refreshing the principle, explaining it to a teammate |
| `resources/kotlin.md` | Idiomatic Kotlin per principle — sealed for OCP, `by` delegation for ISP, type variance for LSP, `value class` to dodge LSP traps, function types as zero-cost abstractions for DIP | Designing or refactoring Kotlin code; you know the principle, you want the idiom |
| `resources/spring-boot.md` | Spring-flavoured SOLID — constructor injection as DIP, `@RestControllerAdvice` as OCP, segregated Spring Data interfaces as ISP, `@Profile` as LSP test seam, Spring Modulith events as OCP enabler | Designing a Spring service, deciding bean wiring, choosing between annotations |
| `resources/bad-practices.md` | Catalogue of anti-patterns: god service, `when`-chain on type, `Penguin.fly() throws`, fat repository interface, `@Autowired` field injection, anemic-hybrid class, infrastructure imports in domain. Each entry: smell → why it's wrong → fix | Code review; pre-merge audit; you suspect a violation but can't name it |
| `resources/best-practices.md` | Heuristics, refactor recipes, the canonical refactor order (SRP → DIP → ISP → OCP → LSP), the "reason to change" prompt, PR-review checklist per principle | Planning a refactor; standing up a team convention; running a structured review |
| `resources/cross-references.md` | Bridges to GRASP, GoF, DDD, architecture: SRP ↔ Info Expert ↔ aggregate; OCP ↔ Polymorphism ↔ Strategy/State; DIP ↔ Indirection ↔ ports-and-adapters | Mapping a SOLID violation to a GRASP fix or GoF pattern; preparing for a design discussion that crosses vocabularies |

## Quick reference

| Letter | Principle | Kotlin red flag | Idiomatic fix |
|---|---|---|---|
| **S** | Single Responsibility | Class with > 1 "reason to change"; service with 20 methods spanning domains | Split by reason-to-change into focused services |
| **O** | Open/Closed | `when` chain on type proliferating across files | Sealed interface + per-variant override |
| **L** | Liskov Substitution | Subclass throws `UnsupportedOperationException`; subclass narrows nullability | Split the hierarchy — `Bird` vs `FlyingBird` |
| **I** | Interface Segregation | Implementer forced to throw or stub half the methods | Small per-client-need interfaces; compose them |
| **D** | Dependency Inversion | Concrete class injected where interface would let you swap | Constructor-inject an interface; place impl in `infrastructure/` |

## Core meta-rules

1. **Principles are diagnostic, not prescriptive.** You don't decide to "apply SRP"; you notice a class with several reasons to change and split it. Mechanically applying SOLID up-front gives you over-engineered Java-style abstractions.
2. **Violations cluster.** A god service almost always violates SRP, ISP, *and* DIP at once. Fix one and the others tend to fall into place.
3. **OCP is the most over-applied.** Wait for the second concrete case before introducing a sealed hierarchy or strategy. Premature OCP is the most common over-engineering source.
4. **DIP is what makes architecture work.** Onion, Clean, Hexagonal — they are all DIP at the architectural scale. Volatile dependencies (frameworks, databases, vendor SDKs) point at stable abstractions (the domain), never the reverse.
5. **Spring rewards SOLID.** Constructor injection IS DIP. Segregated Spring Data interfaces ARE ISP. `@RestControllerAdvice` IS OCP. If you fight SOLID in a Spring service, you fight Spring.

## Related skills

- `grasp-patterns` — responsibility assignment vocabulary; SOLID validates class shape, GRASP decides which class
- `gof-patterns` — pattern catalogue; many SOLID-driven refactors land on a named GoF pattern (Strategy, Decorator, Adapter)
- `clean-code-classes` — class-level Kotlin idioms (encapsulation, primary-constructor properties, weasel-suffix ban) that *implement* SRP
- `clean-code-objects-and-data` — Tell-Don't-Ask, Law of Demeter, anemic-domain anti-pattern; the object-vs-data axis is orthogonal to SOLID but reinforces SRP and DIP
- `clean-code-functions` — function-level discipline; SRP at the function scope ("do one thing")
- `architecture-patterns` — where DIP operates at module / layer scale (Onion, Clean, Hexagonal)
- `ddd-tactical-patterns` — Aggregate root is GRASP's Info Expert with bounded-context discipline; aggregate methods own their data (SRP + DIP at domain scope)
- `architect-review` — apply SOLID during architecture review

## Limitations

- SOLID is object-oriented. For pure functional Kotlin (Arrow, structured concurrency, function composition), the vocabulary shifts toward category theory — out of scope here.
- Don't apply mechanically. A controller with four endpoints is **not** an SRP violation; it's the HTTP boundary for a context. Don't split into `RegisterController`/`LoginController` unless they live in different bounded contexts.
- LSP is the easiest principle to violate accidentally and the hardest to spot in code review. The `bad-practices.md` checklist for LSP is worth memorising.
