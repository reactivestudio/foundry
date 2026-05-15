# Kotlin / JVM — module-level boundary enforcement

Strategic DDD is language-agnostic, but a few Kotlin-stack details affect *how cleanly* boundaries hold once drawn. None of these change WHERE the lines fall — only how the build enforces them.

## Module = bounded context, by default

In a Gradle multi-module project, one BC per subproject:

```
fleet/
├── routing/              # Core BC
├── routing-api/          # Core's published contract (events, IDs, DTOs)
├── auth/                 # Generic BC — Auth0 adapter
├── billing/              # Generic BC — Stripe adapter
├── support/              # Supporting BC
└── platform/             # cross-cutting infra (logging, config, observability)
```

Subprojects can't accidentally import each other's `internal` symbols; cross-module dependencies are explicit in `build.gradle.kts`. **The dependency graph IS the context map, enforced at compile time.**

## `internal` is module-scoped, not package-scoped

Kotlin's `internal` visibility is module-scoped — useful only when each BC is its own Gradle module. Within a single module, there's no package-private; anything `public` (the default) leaks across packages. A "package-per-BC" layout in one module gives no compile-time boundary enforcement.

If the project isn't multi-module yet, fall back to **build-time** boundary checks (Detekt rules, ArchUnit tests) that fail builds on cross-BC imports. Don't rely on naming convention alone.

## Application of `theory.md` "Physical = logical default"

Multi-module Gradle is the cheapest way to enforce BC boundaries on the JVM. **One application, many modules, one deployable** — fine. Premature microservice extraction is a separate decision (load, team scaling), not a strategic-DDD output.
