# TODO
// Strategic patterns
1. bounded-context-design - Определение BC границ по ubiquitous language. Context Map. Признаки правильных и неправильных границ
2. context-mapping - Паттерны: Shared Kernel, Customer-Supplier, Conformist, Anti-Corruption Layer, Open Host Service, Published Language.
3. ubiquitous-language – Формирование и документирование ubiquitous language. Glossary. Как избежать двусмысленности.
4. subdomain-analysis - Core / Supporting / Generic subdomains. Что строить самим, что покупать, где сосредоточить усилия.
5. event-storming – Big Picture / Process / Design level event storming. Обозначения, facilitation. Вывод BC из event storming.
6. domain-storytelling – Визуализация бизнес-процессов через акторов и рабочие предметы. Альтернатива event storming.

// Tactical patterns
1. aggregate-design – Aggregate root, инварианты, consistency boundary. Правила размера: small aggregates. Ссылки по ID.
2. entity-design – Identity, lifecycle, mutability. Отличие от Value Objects. Когда использовать entity vs value object.
3. value-object-design – Immutability, structural equality, self-validation. Kotlin data class как VO. Primitive Obsession решение.
4. domain-service-design – Когда логика не принадлежит entity/VO — domain service. Stateless, операции над несколькими агрегатами.
5. repository-design – Repository как коллекция агрегатов. Интерфейс в domain, реализация в infrastructure. Spec паттерн.
6. factory-design – Domain factories для сложной инициализации агрегатов. Factory method vs отдельный Factory объект.
7. domain-events-design – Именование (прошедшее время), содержимое, когда публиковать. Внутренние vs интеграционные события.
8. domain-events-kotlin – Реализация domain events в Kotlin + Spring. sealed class для событий, ApplicationEventPublisher.
9. integration-events – Публикация событий наружу BC через Kafka/RabbitMQ. Outbox паттерн для надёжности.
10. specification-pattern – Encapsulation бизнес-правил в Specification объекты. Комбинирование (AND/OR/NOT). Query объекты.
11. anti-corruption-layer – ACL реализация между BC. Translator, Facade паттерны. Защита domain model от внешних моделей.
12. saga-design – Distributed процессы через Saga. Choreography vs orchestration. Compensating transactions дизайн.

// Documentation
1. domain-model-doc – Документирование domain model: aggregates diagram, ubiquitous language glossary, BC context map.
2. domain-model-mermaid – Mermaid диаграммы для domain model в markdown. Entity relationships, aggregate boundaries.
3. event-catalog – Каталог domain events: имя, payload, когда публикуется, кто подписан. AsyncAPI формат.
4. bc-spec-format – Стандартный формат спеки для BC в OpenSpec: ubiquitous language, aggregates, invariants, events.
5. invariants-doc – Документирование бизнес-инвариантов агрегатов. Формат для передачи code-implementor.
