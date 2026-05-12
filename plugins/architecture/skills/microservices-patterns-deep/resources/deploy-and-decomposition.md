# Deploy Strategies, Strangler Pattern, Context Propagation, Config & Secrets

The operational glue across services. Decomposition path. Cross-cutting infra patterns.

---

## 1. Deployment strategies

| Strategy | What | Trade-off |
|---|---|---|
| **Rolling** | Replace N% of instances at a time | Simple, default in K8s. Cannot easily rollback during deploy. |
| **Blue-green** | Two full environments; flip traffic | Instant rollback, but 2× resources for the deploy window |
| **Canary** | Send X% traffic to new version, monitor, expand | Gradual, observable. Needs traffic routing. |
| **Shadow / Dark launch** | Mirror prod traffic to new version, don't expose | Test on real traffic without risk |
| **Feature flag** | New code shipped but disabled by flag | Code-level rollback; rich gradual rollouts |

### Picking

- **Default**: rolling (K8s default).
- **Risk-averse changes** (DB migration, schema): blue-green or feature flag.
- **Major version**: canary.
- **Pure read-side new code**: shadow.
- **Per-user-segment rollout**: feature flag.

---

## 2. Canary deployment in practice

Two layers usually involved:

### Layer 1: Gateway / Mesh splits traffic

Spring Cloud Gateway:
```kotlin
@Bean
fun routes(builder: RouteLocatorBuilder): RouteLocator = builder.routes {
    route("orders-canary") {
        path("/api/v1/orders/**")
        weight("orders", 10)             // 10% to canary
        uri("lb://order-service-canary")
    }
    route("orders-stable") {
        path("/api/v1/orders/**")
        weight("orders", 90)             // 90% to stable
        uri("lb://order-service-stable")
    }
}
```

Or in Istio:
```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: order-service
spec:
  http:
    - route:
        - destination:
            host: order-service
            subset: v1
          weight: 90
        - destination:
            host: order-service
            subset: v2
          weight: 10
```

### Layer 2: Auto-progressive rollout

Argo Rollouts or Flagger automate progression based on metrics:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: order-service
spec:
  strategy:
    canary:
      steps:
        - setWeight: 10
        - pause: { duration: 5m }
        - analysis:
            templates:
              - templateName: success-rate
            args:
              - name: service-name
                value: order-service
        - setWeight: 30
        - pause: { duration: 10m }
        - setWeight: 60
        - pause: { duration: 10m }
        - setWeight: 100
```

`AnalysisTemplate` reads Prometheus: if `success_rate < 99%`, roll back automatically.

### Manual canary

If no Argo: deploy canary manually, watch dashboards, ramp manually. Slower but works.

---

## 3. Feature flags

Code is deployed; behaviour is toggled by config.

```kotlin
@Service
class OrderService(
    private val featureFlags: FeatureFlagClient,
) {
    fun processOrder(order: Order) {
        if (featureFlags.isEnabled("new-pricing-engine", userId = order.customerId)) {
            newPricingEngine.price(order)
        } else {
            legacyPricingEngine.price(order)
        }
    }
}
```

Tools: LaunchDarkly, Unleash (self-hosted), GrowthBook (self-hosted), or DIY with Spring Cloud Config.

### Patterns

- **Boolean flag**: on/off
- **Percentage rollout**: enabled for X% of users (consistent hash on user ID)
- **Targeted rollout**: enabled for specific user IDs / tenant IDs / regions
- **Kill switch**: emergency disable of a feature in prod

### Caveats

- **Flag debt.** Old flags accumulate; clean up after rollout completes.
- **Long-lived flags become permanent branches.** Code bifurcates; maintenance cost grows.
- **Flag changes are deployments.** Treat config updates with same rigor as code.

---

## 4. Strangler pattern (monolith → services)

Named after the strangler fig tree: gradually replace the old system.

```
Phase 0: Monolith handles everything.
                  ┌──────────┐
   Clients ────→ │ Monolith │
                  └──────────┘

Phase 1: New service handles a small slice. Routing layer in front.
                  ┌──────────────┐
   Clients ────→ │   Gateway     │
                  └──────────────┘
                    │       │
                    ↓       ↓
              ┌──────────┐  ┌─────────────────┐
              │ Monolith │  │ Order Service   │ (new)
              └──────────┘  └─────────────────┘
              (everything   (just orders)
               but orders)

Phase N: Most slices migrated. Monolith shrinks.
                  ┌──────────────┐
   Clients ────→ │   Gateway     │
                  └──────────────┘
                    │   │   │   │
                    ↓   ↓   ↓   ↓
              [Order] [Cust] [Bill] [Stock]

Phase Final: Monolith is gone.
```

### Steps for each slice

1. **Identify a slice** with clear boundary (often a bounded context with weak coupling to monolith)
2. **Extract the new service** with its own DB schema (or fork a schema from monolith)
3. **Build dual-write phase**: both monolith and new service maintain the data; verify consistency
4. **Cut over reads** to new service via gateway routing
5. **Cut over writes** to new service
6. **Remove the slice from monolith**

### Anti-patterns

- **"Big bang" replatform** — months of work, no shipping, fails 70% of the time
- **Extracting the most coupled slice first** — pain front-loaded; team loses momentum
- **Extracting without team ownership** — service has no owner; rots
- **No path to "monolith is gone"** — strangler stuck at 50%, both systems forever

Pick slices with:
- Clear boundary in monolith
- Active development (so migration value is high)
- Team ready to own it

---

## 5. Distributed tracing — propagation

For request-scoped context (trace ID, span ID), use W3C TraceContext:

```
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
              ^^ ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ^^^^^^^^^^^^^^^^ ^^
              version  trace-id (32 hex)           parent-span-id    flags
```

### HTTP

```kotlin
// WebClient propagates W3C headers automatically with OTel instrumentation
val response = webClient.get()
    .uri("/api/v1/orders/$id")
    .retrieve()
    .bodyToMono<OrderResponse>()

// Headers sent: traceparent, tracestate (automatic with Micrometer Tracing / OpenTelemetry)
```

Spring Boot 3 + Micrometer Tracing auto-propagates. Set:

```yaml
management:
  tracing:
    sampling:
      probability: 1.0          # 100% in dev; 0.01-0.1 in prod
  zipkin:
    tracing:
      endpoint: http://tempo:9411/api/v2/spans
```

### Messaging (RabbitMQ, Kafka)

Manual or via OTel instrumentation.

```kotlin
@RabbitListener(queues = ["events"])
fun handle(@Payload event: Event,
           @Header("traceparent") traceparent: String?,
           @Header("tracestate") tracestate: String?) {
    // Manually start a new span as child of incoming trace
    val context = traceparent?.let { extractContext(it, tracestate) }
    tracer.spanBuilder("handle-event").setParent(context).startSpan().use {
        process(event)
    }
}
```

`org.springframework.amqp:spring-rabbit` + Micrometer Tracing has instrumentation that does this for you when configured. Verify in trace UI.

### Coroutines

```kotlin
suspend fun process() {
    coroutineScope {
        async { downstreamA() }
        async { downstreamB() }
    }.await()
}
```

Trace propagation requires `MDCContext` or OTel context propagation:

```kotlin
launch(Dispatchers.IO + currentCoroutineContext()) {
    // Inherits parent span via OTel context propagation
    downstreamCall()
}
```

OTel's Kotlin extensions handle this automatically when configured.

### MDC for logging correlation

```kotlin
@Component
class CorrelationIdFilter : OncePerRequestFilter() {
    override fun doFilterInternal(req: HttpServletRequest, res: HttpServletResponse, chain: FilterChain) {
        val traceId = Span.current().spanContext.traceId
        MDC.put("traceId", traceId)
        MDC.put("tenantId", extractTenantId(req))
        try { chain.doFilter(req, res) } finally { MDC.clear() }
    }
}
```

Logback pattern:
```xml
<pattern>%d{ISO8601} [%X{traceId} %X{tenantId}] %-5level [%thread] %logger{36} - %msg%n</pattern>
```

Now every log line has trace ID — searchable in Loki/ELK.

---

## 6. Config management

### Spring Cloud Config Server

Centralised git-backed config:

```yaml
# config-repo: application.yml, application-prod.yml, order-service.yml, ...
spring:
  cloud:
    config:
      server:
        git:
          uri: https://github.com/example/config-repo
```

Clients:
```yaml
spring:
  application:
    name: order-service
  config:
    import: "configserver:http://config-server:8888"
```

### Consul KV

```kotlin
spring:
  cloud:
    consul:
      config:
        enabled: true
        prefixes: assista/config
        format: yaml
```

### K8s ConfigMap

Simpler, K8s-native:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: order-service-config
data:
  application.yml: |
    feature.new-pricing: true
    api.github.timeout: 5s
```

Mount as file in pod; Spring loads it.

### Pick one

- Spring Cloud Config: traditional, git-based, rich versioning.
- Consul KV: pairs with Consul discovery; tunable.
- K8s ConfigMap: simplest if you're already on K8s.

**Anti-pattern**: mixing. One config source per service.

### Dynamic config refresh

For runtime updates without restart:

```kotlin
@Component
@RefreshScope
class FeatureToggler(@Value("\${feature.new-pricing}") val enabled: Boolean)
```

Spring Cloud Bus + Actuator `/refresh` endpoint propagate config changes. Or use a feature flag service instead — it's the same idea, better tooling.

---

## 7. Secret management

### Don't put secrets in:
- Config files committed to git
- Plaintext env vars in K8s deployments
- Logs (even error logs)
- Stack traces in API responses

### Solutions

#### HashiCorp Vault

```yaml
spring:
  cloud:
    vault:
      uri: http://vault.internal:8200
      authentication: kubernetes
      kubernetes:
        role: order-service
      kv:
        backend: kv
        application-name: order-service
```

Vault provides:
- Dynamic secrets (e.g., DB credentials that expire)
- Secret rotation
- Audit logging
- Kubernetes-native auth

#### K8s Secrets

Basic but works:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: order-service-secrets
type: Opaque
stringData:
  DB_PASSWORD: ${DB_PASSWORD}
```

Mount as env var or file.

**Problem:** stored as base64 (not encrypted at rest by default in etcd). Use:
- **Sealed Secrets** (Bitnami): encrypt sealed secret, decrypt by controller in cluster
- **External Secrets Operator**: K8s controller that fetches from Vault / AWS Secrets Manager / etc.

### Rotation

For database passwords / API keys:
- Vault dynamic secrets: rotate per request
- External Secrets Operator + AWS Secrets Manager: rotate on schedule, app refreshes
- Manual: planned outage; not a real solution at scale

---

## 8. Cross-cutting observability

What every service must export:

| Signal | Tool |
|---|---|
| **Metrics** | Micrometer → Prometheus |
| **Traces** | OpenTelemetry → Tempo / Jaeger |
| **Logs** | Logback → Loki / ELK (with `traceId` MDC) |
| **Health** | Spring Boot Actuator `/actuator/health` |

Standard endpoints in every service:
```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: when_authorized
      probes:
        enabled: true     # liveness / readiness for K8s
  metrics:
    distribution:
      percentiles-histogram:
        http.server.requests: true
  tracing:
    sampling:
      probability: 0.1
```

Liveness probe (`/actuator/health/liveness`): is the app running?
Readiness probe (`/actuator/health/readiness`): is the app ready for traffic?

K8s probes:
```yaml
livenessProbe:
  httpGet: { path: /actuator/health/liveness, port: 8080 }
  initialDelaySeconds: 30
  periodSeconds: 10
readinessProbe:
  httpGet: { path: /actuator/health/readiness, port: 8080 }
  initialDelaySeconds: 5
  periodSeconds: 5
```

---

## 9. Service boundary checklist

When extracting a slice into a new service, verify all these:

- [ ] API contract designed and documented (REST/gRPC schema)
- [ ] API versioning strategy chosen (URL or header)
- [ ] Auth model: how does caller authenticate (JWT, mTLS, API key)
- [ ] Rate limiting per caller
- [ ] Idempotency for write operations
- [ ] Circuit breaker on calls FROM this service
- [ ] Timeouts on calls FROM this service
- [ ] Trace propagation in (incoming) and out (downstream)
- [ ] MDC fields for tenant/user/correlation
- [ ] Health check endpoints (liveness, readiness)
- [ ] Metrics exported (RED: rate, errors, duration; plus business)
- [ ] Logs structured (JSON) with trace ID
- [ ] Database isolation (own schema, no shared tables)
- [ ] Migration strategy (Flyway per service)
- [ ] Outbox if cross-service writes via events
- [ ] CI/CD pipeline: build, test, security scan, deploy
- [ ] Rollback plan tested
- [ ] On-call runbook (alerts, mitigation steps)
- [ ] Documentation (README, ADRs)

If any unchecked: don't ship.

---

## 10. Multi-region considerations

If the system spans regions:

- **Active-active vs active-passive.** Active-active needs eventual consistency or conflict resolution; active-passive simpler but slower failover.
- **Database replication.** Async (eventual) or sync (latency-prone). Pick per workload.
- **Service-to-service across regions.** Cross-region calls add 50-200ms. Avoid in synchronous paths.
- **Data sovereignty.** EU customers' data must stay in EU? Shard accordingly.
- **DNS / Load balancer for region routing.** GeoDNS, anycast.

Multi-region is a separate skill. Don't drift into it without explicit need.

---

## 11. Common pitfalls

- **No gateway, services directly exposed.** Clients hit each service URL. Auth scattered. Don't.
- **One DB shared across services.** Tightest coupling possible. Defeats microservices.
- **Synchronous deep chains.** P99 multiplies. Use async messaging.
- **No timeouts on calls.** Connection pool exhausts; thread starves; cascade.
- **Strangler stuck at 50%.** Two systems forever. Plan completion at the start.
- **Feature flag debt.** Old flags litter the code. Schedule cleanups.
- **No trace ID in logs.** Debugging across services impossible.
- **No idempotency.** Retries duplicate side effects.
- **No outbox.** "We wrote to DB and Kafka separately" → loses messages on failure.
- **No rollback plan for the deploy strategy.** Blue-green is not "blue-green" without a tested cutover-back.
- **Service-to-service auth via shared secret.** Use mTLS or JWT with short-lived tokens; not shared API keys.
- **Each service inventing its own observability stack.** Standardise: Micrometer + OTel + Logback patterns.
