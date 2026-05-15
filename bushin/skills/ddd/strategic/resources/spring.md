# Spring — strategic boundary leaks

Most Spring content is tactical (aggregates, transactions, repositories) — those land in `ddd-tactical-patterns`. The strategic-relevant pieces are about how Spring's default magic erodes BC boundaries set up at the source-code level.

## Component scanning leaks across BCs

`@SpringBootApplication` on the root package scans every `@Component` on the classpath. If two BCs share a classpath (single deployable, multi-module Gradle), their `@Service` and `@Repository` beans become mutually injectable — the boundary is gone at the framework level even if the source code is in separate modules.

Fix: per-BC `@SpringBootApplication` or explicit `@ComponentScan(basePackages = "...")` scoped to the BC's package. The compile-time boundary (Gradle module) and the framework-time boundary (component-scan scope) must both hold.

## Auto-configuration crosses contexts silently

A library with `META-INF/spring/...AutoConfiguration.imports` registers beans into every Spring context that loads it. JPA auto-config registers `EntityManager` for *every* `@Entity` on the classpath, regardless of which BC owns the entity. Two BCs with entities named `User` — auto-config decides which one wins.

Fix: per-BC `@EntityScan` and `@EnableJpaRepositories` with explicit `basePackages`. Or: per-BC deployment so each BC has its own classpath.

## One `ApplicationContext` per BC, ideally

In a multi-BC modular monolith, the cleanest setup is one Spring `ApplicationContext` per BC, wired together at the integration layer (events, contracts, anti-corruption layers — mechanics in `ddd-context-mapping`). A single shared context — the default — couples BCs at the framework level and undermines the strategic boundary the source-code lines tried to draw.
