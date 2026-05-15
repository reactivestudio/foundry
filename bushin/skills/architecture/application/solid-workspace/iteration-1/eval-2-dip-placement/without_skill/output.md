# Where should `PostgresClient(...)` be constructed?

**Answer: inside a `@Configuration` class, exposed as a `@Bean`. Never inside the service or the repository.**

## The dependency rule

Dependency Inversion (DIP) says high-level policy (services) and the abstractions they consume (repository interfaces) must not depend on low-level details (a concrete Postgres driver). Construction of a concrete detail *is itself a detail* — so the act of calling `new PostgresClient(...)` belongs at the composition root, not inside any class that has a domain or persistence responsibility.

Single Responsibility (SRP) reinforces this: a service's reason to change is business rules; a repository's reason to change is how a particular table is queried. Neither should change when the JDBC URL, pool size, or driver vendor changes.

## Why not the other locations

- **Inside the service** — couples business logic to a specific datastore. The service can no longer be unit-tested without a real Postgres or heavy mocking of a class it shouldn't even know exists. Two responsibilities (orchestrating use cases + wiring infrastructure) collapse into one class.
- **Inside the repository** — better, but still wrong. The repository's job is to translate between domain objects and SQL using a client. Owning the client's lifecycle means it now also reads configuration, manages pooling, and decides shutdown order. It becomes un-substitutable in tests and duplicates wiring across every repository that needs a connection.
- **Static singleton / `new` at field init** — same problems plus hidden global state; defeats Spring's lifecycle, profiles, and `@Primary`/`@Qualifier` selection.

## The correct placement

```java
@Configuration
class PersistenceConfig {
    @Bean(destroyMethod = "close")
    PostgresClient postgresClient(DataSourceProperties props) {
        return new PostgresClient(props.getUrl(), props.getUser(), props.getPassword());
    }
}
```

The repository receives `PostgresClient` (or, better, a narrower interface it abstracts) through constructor injection. The service receives the *repository interface*, never the client.

## Dependency direction summary

```
Service  ──depends on──▶  RepositoryInterface
                                  ▲
                                  │ implements
                         JdbcRepository ──uses──▶ PostgresClient
                                                        ▲
                                                        │ constructed by
                                                  @Configuration  (composition root)
```

Configuration is the only layer allowed to know about *concretes*. Everything above it programs against abstractions. That is DIP in practice: push the `new` to the edge, and let the container — not your domain code — own the wiring.
