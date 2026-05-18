# TODO
// Архитектура
1. arch-constraints-checker – Проверка кода против constraints из app-architecture.md. Нарушения слоёв, forbidden dependencies.
2. dependency-direction-checker – Зависимости идут в правильном направлении? Domain не зависит от Infrastructure? ArchUnit правила.
3. module-boundary-checker – Нарушения модульных границ. Прямой доступ к internal классам другого модуля.
4. pattern-compliance – Используются ли правильные паттерны согласно архитектурным решениям? Отклонения от domain-model.

// SOLID
1. srp-checker – Класс/функция делает одно? Сигналы нарушения SRP: много зависимостей, большой класс, несвязанные методы.
2. ocp-checker – Открыт для расширения, закрыт для изменения? Большие switch/when — сигнал нарушения OCP.
3. lsp-checker – Подтип можно заменить базовым типом? Нарушения контракта в override методах.
4. isp-checker – Интерфейсы не толстые? Клиент не зависит от методов которые не использует.
5. dip-checker – Зависимость от абстракций, не конкретных классов? Правильное использование DI.

// code smells
1. code-smells-detector – Long Method, Large Class, Feature Envy, Data Clumps, Primitive Obsession, Shotgun Surgery, God Class.
2. kotlin-antipatterns – Kotlin-специфичные антипаттерны: nullable hell, misuse of apply/let, lateinit abuse, companion object overuse.
3. spring-antipatterns – Field injection, circular dependencies, @Transactional на private методах, logic в @Configuration.

// Security Review
1. security-checklist – SQL injection (параметризованные запросы?), XSS, CSRF, secrets в коде, authorization checks.
2. input-validation-review – Входные данные валидируются? Правильный слой валидации. @Valid аннотации, custom validators.

// Performance Review
1. n-plus-one-detector – N+1 запросы в JPA. Lazy loading в циклах, missing @EntityGraph, fetch join решения.
2. memory-review – Memory leaks (listeners, caches без eviction), large object allocation в hot paths, String concatenation.
3. concurrency-review – Thread safety, shared mutable state, coroutine misuse, blocking calls в suspend functions.

// Test Review
1. test-quality-review – Тесты проверяют поведение или реализацию? Хрупкие тесты. Meaningful assertions. Arrange-Act-Assert.
2. coverage-review – Покрыты ли happy path, edge cases, error cases? Не гонимся за %, смотрим на смысл.

// Review Format
1. review-output-format – Структурированный вывод: BLOCKER / MAJOR / MINOR / SUGGESTION. Конкретная строка, объяснение, предложение.
2. spec-compliance-report – Сравнение реализации со specs/spec.md. COMPLIANT / DEVIATIONS с конкретными расхождениями.


