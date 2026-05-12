---
name: test-architecture
description: "Architecture fitness functions and mutation testing — the tests that don't verify business behaviour but verify the codebase's structural and quality properties. Three tools: ArchUnit for declarative architecture rules (package dependencies, layer boundaries, naming conventions, annotation usage, no-field-injection, no-JpaRepository-in-controller, no-Spring-imports-in-domain) expressed as JUnit tests; Spring Modulith `ApplicationModuleTest` plus `ApplicationModules.of(...).verify()` for bounded-context boundary enforcement (modules declared by package, internals hidden under `<context>.internal`, cross-module communication only through declared types or events); Pitest for mutation testing — the gold-standard signal for test effectiveness (KILLED = test caught the mutation; SURVIVED = test passed despite the mutation, so write a better assertion; NO_COVERAGE = line wasn't run; healthy production target ~80% kill rate on domain / financial / pricing / scheduling code, skip controllers and repositories). The unifying idea: the fitness-function mindset — every architecture decision is paired with an executable enforcement; ADRs reference the fitness function that locks them in. CI integration: ArchUnit + Modulith `verify()` run with the unit suite (sub-second, fail-fast); Pitest is slow and runs nightly or on critical-module PRs with a mutation-threshold gate. Use this skill whenever the user introduces ArchUnit to a project, writes new package-dependency or layer-boundary rules, adopts Spring Modulith, sets up `ApplicationModuleTest`, runs Pitest on a critical module, debugs a SURVIVED mutation, baselines a legacy codebase under ArchUnit `.allowedViolations()`, or asks 'how do we keep the architecture from rotting?'. For test-suite shape (pyramid / diamond) see test-strategy; for per-test discipline see test-principles; for the layer-specific tests see test-unit / test-integration / test-acceptance / test-contract."
risk: safe
source: "Adapted from existing testing-strategy-kotlin-spring/resources/architecture-tests.md, house practice"
date_added: "2026-05-12"
---

# Test Architecture — Fitness Functions and Mutation Testing

This skill owns the **structural** and **quality-property** tests — the ones that verify the codebase itself, not its runtime behaviour. Three tools cover three distinct concerns: ArchUnit for declarative architecture rules, Spring Modulith for bounded-context boundaries, Pitest for the only objective measure of test *effectiveness*.

> Architecture decisions decay silently unless paired with an executable fitness function. ArchUnit, Modulith, and Pitest are that executable enforcement — the difference between an ADR that holds the line and an ADR that becomes a museum piece six months in.

These tests run with the unit suite (ArchUnit, Modulith) or on a gated schedule (Pitest). They share a single purpose: **keep the codebase from drifting away from its intended shape as it evolves**.

## Use this skill when

- Introducing ArchUnit to a project for the first time, writing new package-dependency rules, layer-boundary rules, or naming-convention rules.
- Adopting Spring Modulith — declaring modules via package layout, writing `ApplicationModules.of(...).verify()`, designing `@ApplicationModuleTest` for cross-module event flows.
- Setting up Pitest on a domain / pricing / financial module and choosing a mutation threshold.
- Debugging a SURVIVED mutation — diagnosing whether the test exercised the line, asserted on the result, or relied on equivalent-behaviour downstream.
- Baselining ArchUnit on a legacy codebase with `.allowedViolations()` and ratcheting the violation count downward.
- Pairing an ADR (architecture decision record) with the fitness function that enforces it — so the decision is not just documented but *defended* by CI.
- Detecting cyclic dependencies (`slices().beFreeOfCycles()`), verifying layered architecture (`layeredArchitecture().consideringAllDependencies()`), or onion architecture (`onionArchitecture()`).
- Enforcing a "domain has no Spring / no JPA imports" rule in a hexagonal codebase.
- Diagnosing why a Modulith `verify()` fails — usually a package-private leak or an undeclared cross-module dependency.
- Asking "how do we keep the architecture from rotting?" — that's literally what this skill answers.

## Do not use this skill when

- Picking the *shape* of the suite (pyramid / diamond / inverted) — that's `test-strategy`.
- Writing or reviewing a single test for clarity, F.I.R.S.T., or BUILD-OPERATE-CHECK — that's `test-principles`.
- Writing unit tests for domain aggregates — that's `test-unit`.
- Writing integration tests with Testcontainers / Spring slices — that's `test-integration`.
- Writing use-case-level acceptance tests — that's `test-acceptance`.
- Writing consumer-driven contracts — that's `test-contract`.
- Designing the architecture itself (choosing hexagonal / onion / modular monolith) — that's `architecture-patterns` and `architecture-decision-records`. *This* skill turns the chosen architecture into an executable rule.

## Selective Reading Rule

The three resources are organised by **tool**, because each tool covers a distinct concern with little overlap. Read the one(s) you need.

| File | Description | When to read |
|---|---|---|
| `resources/archunit.md` | ArchUnit setup, `@AnalyzeClasses` + `@ArchTest` idiom, package-dependency rules, layered / onion architecture verification, naming conventions, anti-pattern detection (no-JpaRepository-in-controller, no-field-injection, no-Spring-imports-in-domain), cyclic-dependency detection, legacy baseline with `.allowedViolations()`, Kotlin examples. | Adding ArchUnit, writing a new rule, baselining a legacy codebase, or debugging a violation. |
| `resources/modulith.md` | Spring Modulith setup, package-based module declaration (`<context>` public, `<context>.internal` private), `ApplicationModules.of(...).verify()`, `@ApplicationModuleTest`, `BootstrapMode.DIRECT_DEPENDENCIES`, `PublishedEvents` assertions, Documenter (PlantUML / AsciiDoc), Modulith-vs-ArchUnit comparison, realistic bounded-context examples (orders, billing, inventory). | Adopting Modulith, declaring a new bounded context, writing a cross-module event-flow test, or debugging a failed `verify()`. |
| `resources/mutation.md` | What mutation testing is, Pitest Gradle plugin setup, scoping with `targetClasses`, mutation operators, interpreting KILLED / SURVIVED / NO_COVERAGE, the SURVIVED diagnosis cycle, where Pitest pays (domain / pricing / scheduling) vs where it doesn't (controllers / repos / DTOs), threshold targets (~80% healthy, 100% overfitted), CI scheduling (nightly / per-PR critical modules), a worked SURVIVED example with the fix. | Setting up Pitest, choosing a threshold, diagnosing a SURVIVED mutation, or deciding whether to run Pitest on a given module. |

## The three tools at a glance

| Tool | What it verifies | Speed | When to use |
|---|---|---|---|
| **ArchUnit** | Static structural rules: package dependencies, layer boundaries, naming, annotation usage, cycles. JUnit tests written in Kotlin/Java. | Sub-second on most codebases. Runs with unit suite. | Anywhere you have an architectural rule worth defending in CI — layers, hexagonal boundaries, naming conventions, forbidden imports. The general-purpose tool. |
| **Spring Modulith** | Bounded-context boundaries inside the same JVM: package-private hiding, cross-module dependencies, declared events. Opinionated, Spring-specific. | Sub-second `verify()` on most modules. `@ApplicationModuleTest` boots one module + dependencies — much faster than `@SpringBootTest`. | Modular monolith where each top-level package is a bounded context. Use *with* ArchUnit (Modulith for modules, ArchUnit for finer-grained rules). |
| **Pitest** | Test *effectiveness* — does the test actually fail when the production code changes? Mutates code, runs tests, reports SURVIVED / KILLED / NO_COVERAGE. | Slow — minutes to hours depending on scope. Nightly or per-PR on critical modules. | Domain layer with rich invariants — aggregates, value objects, pricing, scheduling, financial logic. Not controllers, not repositories, not DTOs. |

## Fitness functions — the mindset

A **fitness function** is an automated check that the system is evolving in the intended direction. Just as unit tests catch behavioural regressions, fitness functions catch **architectural** regressions:

- An ArchUnit rule fails → someone broke a layer boundary; CI blocks the PR.
- A Modulith `verify()` fails → a cross-module dependency was added without a contract; CI blocks the PR.
- A Pitest threshold drops → tests got weaker; CI blocks the PR (when gated).

The discipline is to **pair every architectural decision with the fitness function that enforces it**. The ADR documents the *what* and the *why*; the fitness function defends the *what* against drift. Without the fitness function, the ADR becomes documentation that the code stopped following six months ago and nobody noticed.

Concretely:

> **ADR-0017 — Domain layer has no framework imports.**
> *Decision:* Domain code may not depend on Spring, Jakarta Persistence, Hibernate, or any other framework. Adapters in `..infrastructure..` own all framework integrations.
> *Fitness function:* `ArchitectureTest.\`domain layer is Spring/JPA free\`` enforces this with an ArchUnit `noClasses().that().resideInAPackage("..domain..").should().dependOnClassesThat().resideInAnyPackage("org.springframework..", "jakarta.persistence..", "org.hibernate..")` rule. CI fails the PR on violation.

Every architectural decision worth recording is worth pairing with a fitness function. If a rule can't be expressed as one, it's probably too vague to enforce — sharpen the rule first, then write the fitness function, then write the ADR.

## ArchUnit — declarative architecture rules (summary)

ArchUnit reads compiled classes and lets you express invariants as JUnit tests:

```kotlin
@AnalyzeClasses(packages = ["pro.vlprojects.assista.platform"])
class ArchitectureTest {

    @ArchTest
    val `domain layer is Spring/JPA free`: ArchRule =
        noClasses().that().resideInAPackage("..domain..")
            .should().dependOnClassesThat().resideInAnyPackage(
                "org.springframework..",
                "jakarta.persistence..",
                "org.hibernate..",
            )

    @ArchTest
    val `no field injection`: ArchRule =
        noFields().should().beAnnotatedWith(
            "org.springframework.beans.factory.annotation.Autowired"
        )

    @ArchTest
    val `no cyclic dependencies between modules`: ArchRule =
        slices().matching("pro.vlprojects.assista.platform.module.(*)..")
            .should().beFreeOfCycles()
}
```

The categories of rule that earn their place:

- **Layer / package dependencies** — domain doesn't depend on infrastructure; controllers don't depend on repositories directly.
- **Hexagonal / onion direction** — dependencies point inward; adapters depend on ports, not the other way around.
- **Anti-pattern detection** — no field injection, no `JpaRepository` injected into controllers, no `@Entity` returned from controllers.
- **Naming conventions** — `Service` ends with `Service`, JPA entities end with `JpaEntity`, tests end with `Test` / `IT` / `Spec`.
- **Cyclic dependencies** — `slices().beFreeOfCycles()` catches the worst kind of architectural rot.

What **not** to put in ArchUnit:

- Rules that flap with every refactor (overly specific name constraints; rules that don't survive a legitimate move).
- Strict naming on a legacy codebase before you've baselined — you'll get a hundred failures on first run.
- Rules that encode taste rather than architecture ("methods should be < 20 lines" — that's a `clean-code-functions` concern, not a fitness function).

See `resources/archunit.md` for the deep dive.

## Spring Modulith — bounded-context enforcement (summary)

Spring Modulith treats each top-level package under your application root as a **module** (= bounded context). Public types live in `<context>`; internals live in `<context>.internal` (Spring Modulith automatically treats `internal` as package-private to the module).

```kotlin
class ModularityTest {
    private val modules = ApplicationModules.of(AssistaPlatformApplication::class.java)

    @Test
    fun `verify module structure`() {
        modules.verify()
    }
}
```

`modules.verify()` enforces:

- No internal class is referenced from outside its module.
- No cross-module dependency without a declared exposed type or event.
- Module dependency graph is consistent (declared dependencies match actual references).

`@ApplicationModuleTest` boots a *single* module plus its dependencies — much faster than `@SpringBootTest` — and `PublishedEvents` lets you assert event flow inside the module test.

**Modulith vs ArchUnit:**

| | Modulith | ArchUnit |
|---|---|---|
| Scope | Bounded contexts in the same JVM (Spring-specific) | Any structural rule over compiled classes |
| Opinions | Strong — modules = top-level packages, internals = `.internal` | None — you write the rules |
| Pairing | Use **with** ArchUnit, not instead of it | Use **with** Modulith, not instead of it |

Use both: Modulith for module boundaries, ArchUnit for everything else (layer rules, naming, anti-patterns, cycles).

See `resources/modulith.md` for the deep dive.

## Pitest — mutation testing (summary)

Pitest mutates your production code (changes `+` to `-`, removes if-checks, returns `null` instead of the real value, etc.), reruns the tests against each mutant, and reports:

- **KILLED** — a test failed on the mutant. Good. The test actually exercises the behaviour and asserts on it.
- **SURVIVED** — every test passed on the mutant. **Bad.** The mutation changed the behaviour but no assertion caught it. The test is ineffective.
- **NO_COVERAGE** — no test exercised the mutated line at all.

```kotlin
pitest {
    junit5PluginVersion = "1.2.1"
    targetClasses = listOf("pro.vlprojects.assista.platform.module.*.domain.*")
    threads = 4
    mutationThreshold = 80
    coverageThreshold = 80
}
```

**Where Pitest pays:** domain aggregates, value objects, pricing logic, scheduling, financial calculations, complex control flow with invariants.

**Where Pitest doesn't pay:** controllers (mostly delegation), repositories (Testcontainers covers actual behaviour), DTOs / data classes (no decisions to mutate).

**Threshold target:** ~80% kill rate is a healthy production goal for domain code. 100% drives weird tests that overfit to the implementation. The remaining ~20% is typically defensive code, equivalent mutants, or boundary conditions that aren't worth a separate assertion.

**Interpreting a SURVIVED mutation** (the diagnosis cycle):

1. The test exercises the line but doesn't assert on the result → tighten the assertion.
2. The test exists, but the mutation produces equivalent behaviour for the inputs the test uses → either add an input that distinguishes, or accept it as an equivalent mutant.
3. The line is in an untested branch → add a test for that branch.

See `resources/mutation.md` for the deep dive plus a worked example.

## CI integration

Architecture tests **must** run in CI; otherwise they're advisory and the team discovers violations on `main`. The split:

- **ArchUnit + Modulith `verify()`** — run with the unit suite, every commit. Sub-second. Fail fast.
- **Pitest** — slow. Two options:
  1. Nightly job on the whole project (or a critical-module scope).
  2. Per-PR on modules touched by the PR, with a `mutationThreshold` gate.

Typical Gradle wiring:

```kotlin
tasks.check {
    dependsOn("test", "integrationTest")
    // pitest runs as its own task, gated by CI workflow
}
```

GitHub Actions (sketch):

```yaml
jobs:
  test:
    steps:
      - name: Architecture + unit tests
        run: ./gradlew check -x integrationTest
      - name: Integration tests
        run: ./gradlew integrationTest
      - name: Mutation testing (nightly)
        if: github.event_name == 'schedule'
        run: ./gradlew pitest
```

Architecture tests should run **first** — they fail in milliseconds, and there's no point running the rest of the suite if a layer boundary just got violated.

## Anti-patterns

- **Rules too strict for the team's adoption velocity.** Layer rules that break every new feature. Start permissive; tighten as you learn the codebase shape. Calibrate to the project's actual ergonomics, not to a textbook ideal.
- **No baseline before first adoption.** Adding ArchUnit to a legacy codebase produces hundreds of failures on day one — and the team turns it off. Use `.allowedViolations()` to capture the current state, then ratchet down with each PR.
- **Modulith `verify()` not in CI.** Discovery happens too late — usually when a junior pushes a cross-module call to `main` and the next feature is built on top of it.
- **Pitest on the whole codebase.** Slow (hours on a large project) and most of the surface (controllers, repositories, DTOs) is low-ROI. Scope to the modules where mutation kill rate is a meaningful signal — domain, pricing, scheduling, financial.
- **Mutation threshold chased to 100%.** Drives weird, overfitted tests. ~80% is the production target; the remaining mutants are mostly equivalent or low-value.
- **Fitness functions without ADRs (or ADRs without fitness functions).** Half the discipline is documenting the *why*; half is enforcing the *what*. One without the other rots.
- **Forgetting `@ArchTest` on a `val` of type `ArchRule`.** Silent skip — the rule doesn't run. Always pair with `@AnalyzeClasses` at class level.
- **Treating ArchUnit / Modulith as substitutes for design review.** They catch structural violations of *already-decided* rules. They don't pick the right architecture — that's `architecture-patterns`, `ddd-tactical-patterns`.

## Related skills

| Skill | Why |
|---|---|
| `test` | Router for the testing skill family. |
| `test-strategy` | Picks the suite shape (pyramid / diamond / inverted). This skill is shape-independent — fitness functions exist regardless of where the suite's centre of gravity sits. |
| `test-principles` | Per-test discipline (F.I.R.S.T., BUILD-OPERATE-CHECK). Pitest is the empirical measurement of Khorikov's "protection against regressions" pillar. |
| `test-unit` | The behavioural unit tests that Pitest measures. |
| `test-integration` | Integration tests live alongside ArchUnit / Modulith verifications. |
| `test-acceptance` | Use-case-level tests; `@ApplicationModuleTest` is sometimes the right vehicle. |
| `test-contract` | Sibling layer — consumer-driven contracts for cross-service compatibility. |
| `architecture-patterns` | Picks the architecture. *This* skill enforces it. |
| `architecture-decision-records` | ADRs pair with fitness functions — the canonical "decision + enforcement" record. |
| `ddd-tactical-patterns` | Bounded contexts map to Modulith modules. |
| `clean-code-systems` | System-level discipline (no field injection, dependency direction, public-API hygiene) that ArchUnit enforces in CI. |
| `spring-boot-mastery` | Modulith is a Spring concern; package layout and event publishing follow Spring conventions. |
| `methodology-verification` | After adding or changing a fitness function, run the suite in the current session — "should pass" is not evidence. |
| `methodology-karpathy-guidelines` | Verifiable success criteria — fitness functions *are* verifiable success criteria for architectural decisions. |
| `debugging-systematic` | When ArchUnit / Modulith / Pitest fails surprisingly, root-cause investigation rather than disabling the rule. |

## Limitations

- **ArchUnit and Modulith verify *static* structure.** They don't catch runtime architectural drift — e.g. a circular dependency mediated by reflection, or a "module" that's structurally correct but semantically tangled. For semantic boundary erosion, code review and DDD discipline are the answer.
- **Pitest produces equivalent mutants.** Some mutations cannot, in principle, be killed because they don't change observable behaviour. ~5–15% of SURVIVED mutants in mature code are equivalent; pursuing 100% is therefore overfitting.
- **Pitest is slow.** Mutation testing the whole project per-commit is not feasible on most codebases. Scope and schedule deliberately.
- **The fitness-function mindset doesn't replace design judgment.** A rule like "no Spring imports in domain" is enforceable; a rule like "domain code should be ergonomic for new joiners" is not. The latter still matters — fitness functions defend rules, they don't write them.
- **Adopting these tools on a legacy codebase requires patience.** Bulk-failing on first adoption is the failure mode. Baseline first; ratchet over time; celebrate decreasing violation counts as a metric.
- **Rules can encode bad architecture as durably as good architecture.** A rule that codifies a wrong layer split makes the wrong split harder to fix. Periodically revisit the *rules*, not just the violations.
