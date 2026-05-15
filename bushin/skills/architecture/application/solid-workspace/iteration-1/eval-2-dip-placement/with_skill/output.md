# Where `PostgresClient(...)` should be constructed

Short answer: **in a `@Configuration` class** (Spring's composition root for the module). Not in the service, not in the repository, not in any domain class.

The principle in play is **DIP — Dependency Inversion**. The rule it gives us is operational: *never mention the name of anything concrete and volatile outside the composition root*. `PostgresClient` is the textbook volatile concrete — it ties you to a specific driver, URL, pool, and JDBC contract that change far more often than your business policy.

## Walk through the options against the dependency rule

- **Inside the service class.** Worst option. The service is a use-case/policy class; it must depend only on stable abstractions. The moment `PostgresClient(...)` appears there, the service `import`s a volatile concrete, which is exactly the DIP anti-pattern in the skill's `resources/dip.md`. The domain test now can't run without Postgres — a listed red flag.

- **Inside the repository class.** Better, but still wrong. The repository is the *implementation* of a domain-owned gateway interface (`ReportGateway` in the skill's example). It is allowed to **use** `PostgresClient` — its constructor parameter type may legitimately be `PostgresClient` — but it should not `new` one up. If the repo constructs its own client, you've fused two concerns: "how do I translate domain calls into SQL" and "how is the connection pool wired." That also breaks SRP (two actors: the DBA who tunes pools vs. the team owning the query shape) and makes the repo untestable without a real DB.

- **Inside a `@Configuration` class.** Correct. A `@Bean` method that returns a `PostgresClient` (or more often a `DataSource`/`JdbcTemplate`) is Spring's idiomatic **composition root** — the "small region where concrete components are gathered" that the skill describes as *crossing the curve*. Source-code dependencies from the service and the repository point inward toward the stable `ReportGateway` interface; control flows outward at runtime to the concrete `PostgresReportGateway` holding the injected `PostgresClient`. That opposition is the inversion.

- **Somewhere else?** Spring Boot autoconfiguration counts — `application.yml` plus `spring-boot-starter-jdbc` is effectively a pre-written `@Configuration`. Same rule, just authored by the framework.

## Rule of thumb

`new PostgresClient(...)` is allowed in exactly one kind of file in your module: the `@Configuration` (or `main`) that wires the graph. Everywhere else, accept it through the constructor as the narrowest type you actually use, and prefer the domain-owned interface over the vendor type whenever the caller is policy rather than infrastructure.
