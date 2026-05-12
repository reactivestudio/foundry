---
name: microservices-patterns-deep
description: "Microservices patterns beyond CQRS for Kotlin/Spring services — API gateway (Spring Cloud Gateway, Kong), service discovery (Eureka, Consul, K8s DNS), service mesh (Istio, Linkerd) with mTLS and traffic shaping, resilience (Resilience4j circuit breakers, retries, bulkheads, time limiters, rate limiters), distributed tracing propagation (OpenTelemetry, W3C TraceContext), config server, secret management, deployment strategies (blue-green, canary, shadow), strangler pattern for monolith decomposition. Use when designing or operating a system with multiple services, deciding gateway / mesh / discovery, or hardening cross-service reliability."
risk: safe
source: "custom — microservices patterns for Kotlin/Spring beyond CQRS"
date_added: "2026-05-12"
---

# Microservices Patterns (Deep)

When a system grows past one service, a set of cross-cutting concerns emerges: how do they find each other, how do they secure traffic, how do they degrade gracefully, how do they propagate context, how do they deploy. This skill is **the operational architecture** of a multi-service system — what you reach for after `architecture-patterns` tells you you do need multiple services.

> Microservices solve organisational problems with a technical structure. The technical cost is real. Pay it only when the organisational benefit exceeds it.

## Use this skill when

- Designing service boundaries between 3+ services
- Adding an API gateway (Spring Cloud Gateway, Kong, Envoy)
- Picking service discovery (Eureka, Consul, K8s native)
- Considering a service mesh (Istio, Linkerd)
- Hardening cross-service reliability (Resilience4j: circuit breaker, retry, bulkhead, time limiter, rate limiter)
- Designing tracing propagation (W3C TraceContext, OpenTelemetry)
- Designing config management for many services (Spring Cloud Config, Consul KV)
- Designing secret distribution (HashiCorp Vault, K8s Secrets, SealedSecrets)
- Picking deployment strategy (blue-green, canary, shadow, feature flags)
- Strangler pattern for monolith decomposition

## Do not use this skill when

- You have **one service** — Spring Modulith bounded contexts inside a single deployable cover most architectural needs
- The task is **inside one service** — that's `architecture-patterns`, `cqrs-implementation`
- You're picking **messaging tech** — `messaging-rabbitmq-spring` or future Kafka skill
- The task is **k8s operations / yaml authoring** — ops scope; this skill covers patterns, not platform configuration
- The task is **observability deep** — separate concern; mention here, deep dive elsewhere

## Selective Reading Rule

| File | Description | When to read |
|---|---|---|
| `resources/gateway-discovery-mesh.md` | API Gateway (Spring Cloud Gateway, Kong) — routing, auth, rate limit, transformation; service discovery (Eureka, Consul, K8s DNS); service mesh (Istio, Linkerd) — mTLS, traffic shaping, retry/circuit at network layer; gateway vs mesh decision | Adding gateway, picking discovery, evaluating mesh |
| `resources/resilience-patterns.md` | Resilience4j (circuit breaker, retry, bulkhead, time limiter, rate limiter) for Kotlin/Spring; idempotency; outbox; saga (overview); chaos engineering basics; SLO impact | Hardening cross-service calls, adding circuit breakers, designing retries |
| `resources/deploy-and-decomposition.md` | Deployment strategies (blue-green, canary, shadow, feature flags); strangler pattern for monolith→services; distributed tracing propagation; config management; secrets distribution; cross-cutting observability hooks | Decomposing monolith; designing deploys; tracing/config/secret architecture |

## Core principles

1. **Start with a modular monolith, not microservices.** Spring Modulith bounded contexts give you 80% of the benefits at 5% of the operational cost. Split only when **organisational** scaling demands it (teams need independent deploys).
2. **Every service boundary is an API contract**, with versioning, deprecation, schema discipline. Don't extract a service unless you'd defend the API publicly.
3. **The network is not reliable, fast, or free.** Cross-service calls are 1000× slower than in-process and can fail. Treat them like external HTTP, even on the LAN.
4. **Failures are the default; resilience is the work.** Without circuit breakers, retries, time limits, a cascade is one downstream incident from a global outage.
5. **Propagate the context, always.** Trace ID, tenant ID, user ID — pass through every call. Lost context = unobservable system.
6. **One way of doing each thing.** Mixing service discovery (Eureka + K8s DNS), gateway types (Kong + Spring Cloud Gateway), or auth (JWT + opaque tokens) is operational chaos.
7. **Auto-scale the platform, not the architecture.** If 10× users requires re-architecting, you didn't design for scale. Horizontal scale should be a config change, not a project.
8. **Backward-compatible APIs forever.** You'll never have a deploy window where all services upgrade simultaneously. Plan for v1/v2 coexistence from day one.

## Anti-patterns

- **"Microservices" as a solution to monolith codebase smell.** Refactor the monolith first. Bad code distributed across services = bad code with network calls.
- **Shared database across services.** Defeats the boundary. One service = one DB schema (or carve out tenants explicitly).
- **Synchronous RPC chains 5+ deep.** Latency adds; failures compound. P99 of a 5-deep chain ≈ sum of P99s. Reduce depth or use async messaging.
- **Distributed transaction (2PC).** Almost always wrong. Use sagas or design for compensation; see future saga skill.
- **No gateway at all.** Clients must know about each service, handle auth N times, no rate limiting. Add a gateway from day 2.
- **Gateway as application logic.** Don't put domain logic in the gateway. Stick to routing, auth, rate limit, transform.
- **Service mesh as the FIRST cross-cutting solution.** Operational complexity is real. Use mesh when you have 10+ services and existing observability/resilience pain.
- **No circuit breakers on external calls.** Vendor down → your service hangs → cascade. Always wrap external calls.
- **Retries without exponential backoff or budget.** Naïve retries amplify load on already-struggling downstream → outage.
- **Trace context lost at messaging boundary.** RabbitMQ / Kafka don't propagate W3C TraceContext by default. You wire it.
- **Strangler pattern executed all at once.** "Re-platform" projects fail. Strangle incrementally over many releases.

## When microservices, when modulith

| Sign you need microservices | Sign you should stay monolith / modulith |
|---|---|
| Multiple teams blocking each other's releases | One team owns the code |
| Different scalability needs per area (e.g., search vs writes) | Uniform scaling |
| Different tech requirements (Python ML model vs Kotlin services) | Single stack |
| Different security / compliance domains (PII isolated) | Single security posture |
| Team size > 50 | Team size < 30 |
| Component requires independent release cadence | Releases sync OK |

For a modular monolith (e.g. Spring Modulith with N bounded contexts in one deployable), staying monolithic is usually the right answer until a specific trigger fires. Real triggers for extracting a context into its own service:
- A specific context develops fundamentally different scale or compliance needs (one context drives 80% of traffic; one needs SOC2 isolation; one needs GPU).
- Multiple teams (typically 5+) want independent release ownership of subsets — Conway's Law starts paying you back instead of taxing you.
- Long-running work (real-time streaming, ML inference, batch ETL) actually appears and starves the rest of the JVM.

Without one of those triggers, pre-write the strangler spec but don't pre-split — the operational cost arrives years before the benefit.

## Stack mapping — what Spring/Kotlin shops typically pick

| Concern | Default for a Kotlin/Spring polyglot stack |
|---|---|
| API gateway | Spring Cloud Gateway (Kotlin/Java home) or Kong (mature, language-agnostic) |
| Service discovery | Kubernetes DNS (built-in if on K8s) or Consul |
| Service mesh | Linkerd (lightweight, fast) or Istio (heavy, full-featured) — **only when needed** |
| Auth between services | mTLS at mesh + JWT in app (see `spring-security-and-auth`) |
| Resilience library | Resilience4j (Spring Boot starter exists) |
| Tracing | OpenTelemetry + Tempo / Jaeger |
| Config | Spring Cloud Config Server OR Consul KV OR K8s ConfigMaps |
| Secrets | HashiCorp Vault OR K8s Secrets + SealedSecrets/External Secrets Operator |
| Messaging | RabbitMQ (per your call) for events |
| Deploy | Kubernetes + ArgoCD/Flux (GitOps) |
| Strategy | Canary via gateway weighting OR mesh OR Argo Rollouts |

## Cross-cutting context propagation

Every request/event/message carries:
- **Trace context** (W3C `traceparent`, `tracestate`)
- **Tenant ID** (multi-tenant)
- **User ID / principal** (auth)
- **Correlation ID** (often = trace ID)
- **Idempotency key** (for write operations)
- **Deadline / timeout** (for chained calls)

Implementation:
- HTTP: standard headers (W3C TraceContext, `X-Tenant-Id`, etc.)
- gRPC: metadata
- Messaging: AMQP headers / Kafka headers
- Spring: MDC + `ThreadLocal` for sync; coroutine context for suspending; auto-propagation via Sleuth/Micrometer Tracing

Missing context propagation is the biggest source of "I can't debug this incident across services" pain.

## Related skills

- `architecture` — the decision to go multi-service in the first place
- `architecture-patterns` — internal structure of each service
- `ddd-strategic-design` + `ddd-context-mapping` — how the bounded contexts relate
- `cqrs-implementation` — CQRS within a service
- `messaging-rabbitmq-spring` — async event bus
- `caching-strategies-spring` — Redis as shared L2 cache
- `spring-security-and-auth` — service-to-service auth, mTLS, JWT propagation
- `api-design-principles` — REST/gRPC contracts at service boundaries
- `database-design` — DB per service, cross-service consistency via events
- `jvm-performance` — when latency budget is tight, profile each hop
- `methodology-verification` — verifying deploys, especially canary

## Limitations

- Patterns assume Kotlin/Spring on JVM, Kubernetes-or-similar runtime. Bare-metal / legacy deployments have different operational shape.
- No deep dive on K8s itself, Helm, ArgoCD, Terraform — operations-side. This skill is the application-side patterns.
- Stop and ask if the **driver for microservices** is unclear (org scaling, tech requirement, scale, compliance) — drives every other decision.
