---
name: database-design
description: "Database design for Kotlin/Spring Boot — schema design with Spring Data JPA, indexing for PostgreSQL, polyglot persistence decisions (Postgres / MongoDB / Elasticsearch / Clickhouse), Flyway migrations with zero-downtime patterns, JPA query optimization. Use when designing tables, choosing indexes, picking between stores, or planning schema changes."
risk: safe
source: "custom — database design principles adapted for Kotlin/Spring/Flyway with polyglot persistence stack"
date_added: "2026-05-11"
---

# Database Design (Kotlin / Spring)

Database design principles and decision-making for Kotlin/Spring Boot codebases with a polyglot persistence stack (PostgreSQL primary + MongoDB / Elasticsearch / Clickhouse as needed).

> Think first, choose store after. Most database problems are design problems disguised as performance problems.

## Use this skill when

- Designing a new schema (tables, indexes, relationships, constraints).
- Choosing between **Postgres / Mongo / Elasticsearch / Clickhouse** for a given workload.
- Picking between **Spring Data JPA / Spring Data JDBC / QueryDSL / jOOQ / raw JDBC**.
- Planning a Flyway migration, especially anything that's not a trivial `CREATE TABLE`.
- Investigating slow JPA queries (N+1, eager fetch, missing indexes).
- Deciding what goes in `@Embedded`, what gets its own table, what stays JSONB.

## Do not use this skill when

- The task is **CQRS projection design** — use `cqrs-implementation` (specifically `read-side-patterns.md`).
- The task is **API contract design** — use `api-design-principles`.
- The task is **bounded context layout** — use `architecture-patterns` (Onion / DDD).
- The task is **operational** (backups, monitoring, failover) — out of scope here; that's DBA territory.

## Selective Reading Rule

Read only the file relevant to the current task. Most schema design sessions need 1-2.

| File | Description | When to read |
|---|---|---|
| `resources/schema-design.md` | JPA entities vs domain entities, IDs, timestamps, relationships, embedded VOs, JSONB, multi-tenancy | Designing new tables / entities |
| `resources/orm-and-jpa.md` | Spring Data JPA / JDBC / QueryDSL / jOOQ / raw JDBC — when each wins; Open Session In View; entity-vs-DTO boundary | Choosing data access strategy or refactoring it |
| `resources/polyglot-persistence.md` | When PG / Mongo / ES / Clickhouse — decision tree, cost of each store, cross-store consistency | Picking the right store for a workload |
| `resources/indexing.md` | PostgreSQL indexes (B-tree / GIN / GiST / BRIN / partial / expression), composite ordering, CONCURRENTLY | Choosing or auditing indexes |
| `resources/optimization.md` | EXPLAIN ANALYZE, JPA N+1, JOIN FETCH, EntityGraph, @BatchSize, keyset pagination, batch inserts | Investigating slow queries |
| `resources/migrations.md` | Flyway naming, expand-contract patterns, backfills, CONCURRENTLY indexes, table rename via view | Planning schema changes |

## Core principles

1. **Domain model first, schema second.** The aggregate boundary informs the table boundary, not the other way round. See `architecture-patterns` for the domain layer.
2. **Pick the store for the workload, not the company.** Postgres is the default. Reach for Mongo / ES / Clickhouse only when Postgres genuinely can't do the job.
3. **JPA entities are NOT domain entities.** Especially for aggregates with invariants. JPA `@Entity` is a persistence shape; the domain model is what enforces rules.
4. **Index based on actual queries, not vibes.** Every index has a write cost. Add when `EXPLAIN ANALYZE` says you need it.
5. **Every migration must be zero-downtime-capable.** If not, you're committing to a maintenance window. Plan the expand-contract sequence up front.
6. **`SELECT *` and unbounded `findAll()` are bugs.** Always project what you need; always paginate.

## Anti-patterns (don't do this)

- **`data class` for JPA entities.** Hibernate proxies + `equals`/`hashCode` over all fields = bug factory. See `clean-code-objects-and-data` ("Hybrid: JPA @Entity as data class") for the diagnosis and the regular-class-with-id-equality fix.
- **Defaulting to PostgreSQL JSONB for everything.** "Schema-less" is a smell when the schema is actually well-known and queryable.
- **Reaching for MongoDB because "it's web scale".** It's not your scale problem.
- **Adding indexes "just in case".** Each is a write tax. Justify with a real query.
- **Open Session In View on** (Spring default). Lazy loading in the view layer = N+1 + transaction leaks. Turn it off (`spring.jpa.open-in-view=false`).
- **Eager-fetching `@OneToMany` to "fix N+1".** Now you load 1000 children on every parent read. Use `JOIN FETCH` or `EntityGraph` at the query level.
- **`@OneToMany` without `mappedBy`.** Hibernate creates a join table you didn't ask for.
- **Renaming a column "in one migration".** Old code reading old column + new column missing = production incident. Use expand-contract.
- **Migration without rollback plan.** "Drop column" is destructive. Have a path back if the deploy breaks.

## Spring Boot integration headlines

- **Flyway** is the migration tool. Conventions: `V<N>__description.sql` for versioned, `R__description.sql` for repeatable. `validateMigrationNaming = true` to catch typos at build time.
- **`spring.jpa.open-in-view=false`** — non-negotiable for any service that takes real traffic.
- **HikariCP** is the default pool. Tune size with a formula, not a guess (see `optimization.md`).
- **`@Transactional` boundary at the service layer** — not on repositories, not in controllers.
- **Multi-store** = multi-`@Configuration`. Separate `EntityManagerFactory` / Mongo client / ES client / Clickhouse JDBC datasource, each with its own `@Repository` package.

## Related skills

- `architecture` — when database design is part of a bigger decision (Example 3 covers polyglot)
- `architecture-patterns` — Layered (MVC-style) shows the natural Spring Data JPA layout
- `cqrs-implementation` — for projection design (read side); read `cqrs-implementation/resources/read-side-patterns.md` if the table is a projection target
- `api-design-principles` — for the boundary between DB entity and REST DTO

## Limitations

- Patterns assume Kotlin/Spring Boot + Flyway + HikariCP. For non-Spring or non-JVM stacks, the index/schema principles still apply but the integration points don't.
- The skill covers **design**, not operations (backups, replication setup, monitoring infrastructure) — that's DBA scope.
- Stop and ask if the **expected workload shape** (read-heavy / write-heavy / analytical / mixed) is unclear — it drives every other decision.
