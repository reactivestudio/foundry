# ArchUnit — Declarative Architecture Rules

ArchUnit reads compiled classes and lets you express architectural invariants as JUnit tests. The tests fail when someone breaks a layer boundary, introduces a forbidden import, or creates a cyclic dependency. They run as part of the unit suite (sub-second) and block PRs at the CI gate.

> An ArchUnit rule is a fitness function: the architectural decision in executable form. If a rule can't be expressed as one, the decision is probably too vague to enforce — sharpen the rule first.

This file covers setup, the canonical idioms, the high-ROI categories of rule, the legacy-baseline pattern, and the anti-patterns to avoid.

## 1. Setup

Add the JUnit 5 ArchUnit dependency:

```kotlin
// build.gradle.kts
dependencies {
    testImplementation("com.tngtech.archunit:archunit-junit5:1.3.0")
}
```

That's it. ArchUnit pulls in its own class scanner; it doesn't need a Spring context, doesn't need Testcontainers, and runs in-process at unit-test speed.

If your project has a multi-module Gradle layout, put the architecture test in the module that imports the entire application graph (typically the bootstrap / `:app` module), so all classes are reachable for analysis.

## 2. The canonical idiom — `@AnalyzeClasses` + `@ArchTest`

```kotlin
import com.tngtech.archunit.junit.AnalyzeClasses
import com.tngtech.archunit.junit.ArchTest
import com.tngtech.archunit.lang.ArchRule
import com.tngtech.archunit.lang.syntax.ArchRuleDefinition.*

@AnalyzeClasses(
    packages = ["pro.vlprojects.assista.platform"],
    importOptions = [ImportOption.DoNotIncludeTests::class],
)
class ArchitectureTest {

    @ArchTest
    val `domain layer is Spring/JPA free`: ArchRule =
        noClasses().that().resideInAPackage("..domain..")
            .should().dependOnClassesThat().resideInAnyPackage(
                "org.springframework..",
                "jakarta.persistence..",
                "org.hibernate..",
            )
}
```

Key points:

- `@AnalyzeClasses` declares the package(s) to scan. Use `ImportOption.DoNotIncludeTests` to avoid analyzing test code (otherwise test classes break rules constantly).
- Each rule is a `val` of type `ArchRule` annotated with `@ArchTest`. ArchUnit's JUnit Jupiter integration discovers them automatically.
- **Forgetting `@ArchTest` is a silent skip** — the rule won't run. If you're adding a rule and CI is suspiciously green, check the annotation first.
- Use **backtick names** for the rule — that name appears in the test report, so make it read as a sentence.

For multi-package analysis:

```kotlin
@AnalyzeClasses(packages = [
    "pro.vlprojects.assista.platform.module.orders",
    "pro.vlprojects.assista.platform.module.billing",
])
class OrdersAndBillingArchitectureTest { ... }
```

## 3. Layered architecture verification

The most common rule and the easiest to misuse. ArchUnit's `layeredArchitecture()` DSL declares layers and which-may-access-which:

```kotlin
@ArchTest
val `layered architecture is respected`: ArchRule =
    layeredArchitecture().consideringAllDependencies()
        .layer("Web").definedBy("..controller..", "..web..")
        .layer("Application").definedBy("..application..", "..service..")
        .layer("Domain").definedBy("..domain..")
        .layer("Infrastructure").definedBy("..infrastructure..")
        .whereLayer("Web").mayNotBeAccessedByAnyLayer()
        .whereLayer("Application").mayOnlyBeAccessedByLayers("Web")
        .whereLayer("Domain").mayOnlyBeAccessedByLayers("Application", "Infrastructure")
        .whereLayer("Infrastructure").mayOnlyBeAccessedByLayers("Application")
```

`consideringAllDependencies()` is important — without it, ArchUnit considers only *direct* references, missing dependencies through generics, annotations, or method parameters.

For onion / hexagonal architectures, use the dedicated DSL:

```kotlin
@ArchTest
val `onion dependencies point inward`: ArchRule =
    onionArchitecture()
        .domainModels("..domain.model..")
        .domainServices("..domain.service..")
        .applicationServices("..application..")
        .adapter("persistence", "..infrastructure.persistence..")
        .adapter("web", "..infrastructure.web..")
```

`onionArchitecture()` enforces:

- Domain models depend on nothing outside themselves.
- Domain services depend only on domain models.
- Application services depend on domain only.
- Adapters depend on application + domain; adapters do not depend on each other.

## 4. Package-dependency rules — the bread and butter

```kotlin
@ArchTest
val `controllers only call services`: ArchRule =
    classes().that().resideInAPackage("..controller..")
        .should().onlyDependOnClassesThat()
        .resideInAnyPackage(
            "..controller..",
            "..service..",
            "..dto..",
            "java..",
            "kotlin..",
            "org.springframework.web..",
            "org.springframework.http..",
        )

@ArchTest
val `repositories live in infrastructure`: ArchRule =
    classes().that().areAnnotatedWith(Repository::class.java)
        .should().resideInAPackage("..infrastructure.persistence..")

@ArchTest
val `no entity exposed from controllers`: ArchRule =
    noMethods().that().areDeclaredInClassesThat().resideInAPackage("..controller..")
        .should().haveRawReturnType(JpaEntity::class.java)  // marker interface
```

Note the **`java..` and `kotlin..` allowlist** for the "only depend on" rule — without it, the rule fails on `String`, `List`, etc. This is the trap most teams hit on first adoption.

## 5. Anti-pattern detection rules

These are the highest-ROI rules — they encode "things that should never happen" and are cheap to enforce.

### No `JpaRepository` injection in controllers

```kotlin
@ArchTest
val `no JpaRepository injection in controllers`: ArchRule =
    noClasses().that().resideInAPackage("..controller..")
        .should().dependOnClassesThat().areAssignableTo(JpaRepository::class.java)
```

Controllers that talk to JPA directly bypass the service layer — the classic "transaction script in a controller" smell.

### No field injection

```kotlin
@ArchTest
val `no field injection`: ArchRule =
    noFields().should().beAnnotatedWith("org.springframework.beans.factory.annotation.Autowired")
        .orShould().beAnnotatedWith("jakarta.inject.Inject")
```

Forces constructor injection — see `clean-code-systems` for the design rationale. ArchUnit makes the rule unforgiving.

### No `System.out` / `println` in production

```kotlin
@ArchTest
val `no System out in production code`: ArchRule =
    noClasses().should().callMethod(System::class.java, "out")
```

### Domain has no framework imports

```kotlin
@ArchTest
val `domain layer is Spring/JPA free`: ArchRule =
    noClasses().that().resideInAPackage("..domain..")
        .should().dependOnClassesThat().resideInAnyPackage(
            "org.springframework..",
            "jakarta.persistence..",
            "org.hibernate..",
            "com.fasterxml.jackson..",  // domain shouldn't know about JSON serialisation either
        )
```

The canonical hexagonal rule. Without this, "domain" gradually accumulates framework decoration until it's indistinguishable from infrastructure.

### No `@RestController` returning `@Entity`

```kotlin
@ArchTest
val `controllers do not return JPA entities`: ArchRule =
    noMethods().that().areDeclaredInClassesThat()
        .areAnnotatedWith(RestController::class.java)
        .should().haveRawReturnType { it.isAnnotatedWith(Entity::class.java) }
```

Prevents leaking the persistence model into the API.

## 6. Naming conventions

```kotlin
@ArchTest
val `services end with Service or Handler or UseCase`: ArchRule =
    classes().that().areAnnotatedWith(Service::class.java)
        .should().haveSimpleNameEndingWith("Service")
        .orShould().haveSimpleNameEndingWith("Handler")
        .orShould().haveSimpleNameEndingWith("UseCase")

@ArchTest
val `JPA entities end with JpaEntity`: ArchRule =
    classes().that().areAnnotatedWith(Entity::class.java)
        .should().haveSimpleNameEndingWith("JpaEntity")

@ArchTest
val `controllers end with Controller`: ArchRule =
    classes().that().areAnnotatedWith(RestController::class.java)
        .should().haveSimpleNameEndingWith("Controller")
```

Naming-convention rules pay off when the project has agreed on conventions. They cost when they don't — every divergent class becomes a CI failure. **Don't introduce naming rules until the team has stabilised the conventions.**

## 7. Cyclic dependency detection

The single highest-ROI rule. Catches the worst kind of architectural rot — A→B→A — which is invisible in code review but devastating to maintain.

```kotlin
@ArchTest
val `no cyclic dependencies between modules`: ArchRule =
    slices().matching("pro.vlprojects.assista.platform.module.(*)..")
        .should().beFreeOfCycles()

@ArchTest
val `no cyclic dependencies between packages within a module`: ArchRule =
    slices().matching("pro.vlprojects.assista.platform.module.(*).(*)..")
        .should().beFreeOfCycles()
```

`slices().matching(...)` carves the codebase by the regex group — each unique capture becomes a slice. `beFreeOfCycles()` asserts the slice dependency graph is acyclic.

Add this rule on day one. The cost of removing existing cycles is high; the cost of preventing new ones is near-zero.

## 8. Adopting ArchUnit on a legacy codebase — the baseline

A legacy codebase will fail dozens of rules on first adoption. Don't disable the rule; don't write a giant exception list manually. Use `.allowedViolations()` from `archunit-junit5` (or `archunit_ignore_patterns.txt` in older versions):

```kotlin
@ArchTest
val `domain layer is Spring/JPA free`: ArchRule =
    noClasses().that().resideInAPackage("..domain..")
        .should().dependOnClassesThat().resideInAnyPackage(
            "org.springframework..", "jakarta.persistence..",
        )
        .allowedViolations(
            "pro.vlprojects.legacy.domain.OldOrder.repo",
            "pro.vlprojects.legacy.domain.LegacyCustomer.entityManager",
        )
```

Or, more commonly, capture the freeze file:

1. Run the rule with `FreezingArchRule.freeze(...)` on first adoption.
2. ArchUnit writes the current violations to `archunit_store/`.
3. Subsequent runs allow only those known violations; **any new violation fails**.
4. Each PR that fixes one of the captured violations removes it from the freeze; the count ratchets down.

```kotlin
@ArchTest
val `no field injection`: ArchRule =
    FreezingArchRule.freeze(
        noFields().should().beAnnotatedWith(
            "org.springframework.beans.factory.annotation.Autowired"
        )
    )
```

The freeze file is **checked into git**. PRs that decrease the violation count are merged; PRs that introduce new violations fail.

This is the only sustainable adoption pattern for a non-trivial codebase. The alternative — turning the rule off until "we fix it later" — means the rule never gets turned on.

## 9. Custom rules — when the DSL isn't enough

Sometimes the built-in conditions don't fit. ArchUnit lets you write custom predicates:

```kotlin
val notInstantiatedDirectly = object : ArchCondition<JavaClass>("not be instantiated outside its package") {
    override fun check(item: JavaClass, events: ConditionEvents) {
        item.directDependenciesToSelf
            .filter { it.targetClass == item }
            .filter { it.originClass.packageName != item.packageName }
            .filter { it.descriptionInLocation.contains("instantiates") }
            .forEach { events.add(SimpleConditionEvent.violated(it, it.description)) }
    }
}

@ArchTest
val `aggregates are constructed via factories`: ArchRule =
    classes().that().areAnnotatedWith(AggregateRoot::class.java)
        .should(notInstantiatedDirectly)
```

Custom rules are powerful but invest carefully — they're harder to maintain than DSL rules, and the ArchUnit team will not break the DSL but may break the lower-level API.

## 10. A realistic full rule set — bounded-context modular monolith

```kotlin
@AnalyzeClasses(
    packages = ["pro.vlprojects.assista.platform"],
    importOptions = [ImportOption.DoNotIncludeTests::class],
)
class PlatformArchitectureTest {

    // Layer rules
    @ArchTest
    val `layered architecture is respected`: ArchRule =
        layeredArchitecture().consideringAllDependencies()
            .layer("Controller").definedBy("..controller..")
            .layer("Application").definedBy("..application..")
            .layer("Domain").definedBy("..domain..")
            .layer("Infrastructure").definedBy("..infrastructure..")
            .whereLayer("Controller").mayNotBeAccessedByAnyLayer()
            .whereLayer("Application").mayOnlyBeAccessedByLayers("Controller")
            .whereLayer("Domain").mayOnlyBeAccessedByLayers("Application", "Infrastructure")
            .whereLayer("Infrastructure").mayOnlyBeAccessedByLayers("Application")

    // Domain purity
    @ArchTest
    val `domain layer is Spring/JPA free`: ArchRule =
        noClasses().that().resideInAPackage("..domain..")
            .should().dependOnClassesThat().resideInAnyPackage(
                "org.springframework..",
                "jakarta.persistence..",
                "org.hibernate..",
                "com.fasterxml.jackson..",
            )

    // Cycles
    @ArchTest
    val `no cycles between modules`: ArchRule =
        slices().matching("pro.vlprojects.assista.platform.module.(*)..")
            .should().beFreeOfCycles()

    // Anti-patterns
    @ArchTest
    val `no field injection`: ArchRule =
        noFields().should().beAnnotatedWith(
            "org.springframework.beans.factory.annotation.Autowired"
        )

    @ArchTest
    val `no JpaRepository in controllers`: ArchRule =
        noClasses().that().resideInAPackage("..controller..")
            .should().dependOnClassesThat().areAssignableTo(JpaRepository::class.java)

    @ArchTest
    val `no JPA entity returned from controllers`: ArchRule =
        noMethods().that().areDeclaredInClassesThat()
            .areAnnotatedWith(RestController::class.java)
            .should().haveRawReturnType { it.isAnnotatedWith(Entity::class.java) }

    // Naming
    @ArchTest
    val `JPA entities end with JpaEntity`: ArchRule =
        classes().that().areAnnotatedWith(Entity::class.java)
            .should().haveSimpleNameEndingWith("JpaEntity")
}
```

About a dozen rules total. Each is one to four lines. Together they defend most of the architectural decisions in an ADR portfolio.

## 11. Anti-patterns

- **Rule too strict on first adoption.** A "controllers only depend on services and DTOs" rule with no `java..` / `kotlin..` allowlist fails on `String`. Either calibrate the rule or use `FreezingArchRule`.
- **Naming convention rules before the team agreed conventions.** Every divergent class becomes a CI failure; the team disables the rule. Wait until naming is stable.
- **Layer rules without `consideringAllDependencies()`.** Misses dependencies through generics, annotations, method signatures. Subtle but devastating.
- **Custom rules where DSL would do.** Custom rules are harder to read and maintain. Use them only when the DSL truly can't express the rule.
- **Forgetting `@ArchTest`.** Silent skip — the rule doesn't run. Always pair with `@AnalyzeClasses` and verify the rule is in the test report after adding it.
- **Forgetting `ImportOption.DoNotIncludeTests`.** Test classes will violate "no field injection" via `@MockkBean`, will depend on `@SpringBootTest`, etc. Exclude tests from analysis unless you have a specific reason not to.
- **One giant `ArchitectureTest` class for the entire monolith.** Past ~30 rules it's hard to navigate. Split by concern: `LayerArchitectureTest`, `NamingArchitectureTest`, `ModuleBoundariesArchitectureTest`.
- **Rules that flap on legitimate refactors.** A rule that fails every time someone renames a package is encoding implementation, not architecture. Rewrite it to express the *invariant*, not the *layout*.
- **ArchUnit as a substitute for code review.** It catches structural violations. It doesn't catch bad design, missing abstractions, or unclear naming. Pair with review, don't replace it.
