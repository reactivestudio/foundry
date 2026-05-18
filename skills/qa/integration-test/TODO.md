# TODO
1. @SpringBootTest, @WebMvcTest, @DataJpaTest, @MockBean. Slice тесты для минимального контекста.
2. PostgreSQL, Kafka, Redis через Testcontainers. KotlinExtension. Reusable containers для скорости.
3. Тестирование Repository с реальной БД через Testcontainers. @DataJpaTest + Flyway миграции.
4. EmbeddedKafka vs Testcontainers для тестирования producers/consumers. Await assertions.
5. WireMock для HTTP зависимостей. Stub configurations, verification, record & playback.
