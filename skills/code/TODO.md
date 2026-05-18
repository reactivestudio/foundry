# TODO
// Kotlin
1. kotlin-idioms – Data classes, sealed classes, when expressions, extension functions, scope functions (let/run/apply/also/with).
2. kotlin-coroutines – suspend functions, coroutine builders, Flow, structured concurrency, exception handling, channels.
3. kotlin-functional – Arrow-kt: Either, Option, Validated. Функциональный стиль, railway-oriented programming.
4. kotlin-dsl - Type-safe builders, DSL design. Когда DSL оправдан и как его не переусложнить.
5. kotlin-null-safety – Nullable types, ?: оператор, let, requireNotNull, checkNotNull. Работа с Java nullable API.

// Spring Boot
1. spring-boot-kotlin – Spring Boot + Kotlin специфика: конструктор injection, open классы, kotlin-spring plugin.
2. spring-data-jpa – Repository паттерны, кастомные запросы, проекции, @EntityGraph, N+1 проблема и решения.
3. spring-webmvc – Controllers, request mapping, validation (@Valid), exception handling (@ControllerAdvice), filters.
4. spring-security – SecurityFilterChain, JWT реализация, method-level security, OAuth2 resource server.
5. spring-cache – @Cacheable, @CacheEvict, Redis интеграция, cache configurations, TTL стратегии.

// Algorithms и Data Structures
1. complexity-analysis – Big O notation, time/space complexity. Анализ производительности алгоритмов и коллекций.
2. collections-kotlin – List/Set/Map операции, sequences для ленивых вычислений, performance implications каждой операции.
3. common-algorithms – Sorting, searching, graph traversal, dynamic programming. Kotlin реализации стандартных алгоритмов.

// Implementation Patterns
1. repository-implementation – Реализация Repository паттерна поверх Spring Data. Mapping domain ↔ persistence, custom queries.
2. use-case-implementation – Application layer use cases в Clean/Onion arch. Orchestration logic, transaction boundaries.
3. api-implementation – REST endpoint реализация. Request/Response DTOs, validation, mapping, OpenAPI аннотации.
4. event-implementation – Domain events, event publishing, listeners. Spring Events vs Kafka для внутренних/внешних событий.
5. resilience4j – CircuitBreaker, Retry, RateLimiter, Bulkhead реализация в Spring Boot + Kotlin.

// Code Quality
1. refactoring-patterns – Fowler refactoring catalog: Extract Method/Class, Move, Rename, Introduce Parameter Object, Replace Conditional.
2. detekt-compliance – Detekt правила для Kotlin. Настройка под проект, suppression когда оправдано, custom rules.
3. logging – SLF4J + Logback/Log4j2. Structured logging (JSON), MDC, log levels, что и когда логировать.
4. opentelemetry – Spans, traces, metrics инструментирование в Spring Boot. Micrometer интеграция.

