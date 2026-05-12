# Gateway, Discovery, and Mesh

API Gateway. Service Discovery. Service Mesh. When each. How they interact.

---

## 1. API Gateway — why and what

A gateway sits **between clients and services**. Single ingress for the entire system. Handles:

- **Routing** (path/host-based to backend services)
- **Authentication** (verify JWT, validate API keys)
- **Authorisation** (coarse-grained — fine-grained stays in services)
- **Rate limiting** (per-client / per-route quotas)
- **Request/response transformation** (header injection, version translation)
- **TLS termination** (HTTPS public, HTTP/2 or mTLS to backends)
- **Logging/metrics** (uniform observability for all ingress)
- **Caching** (HTTP response caching at edge)

Without a gateway: clients know every service URL, each service does auth, rate limiting is inconsistent.

---

## 2. Gateway choices

| Tool | Type | Why pick |
|---|---|---|
| **Spring Cloud Gateway** | JVM, reactive (WebFlux) | Same stack as services, code-defined routes, native Spring config |
| **Kong** | OpenResty (nginx + Lua) | Mature, language-agnostic, big plugin ecosystem |
| **Envoy** | C++, very fast | Foundation for Istio; use when you'd otherwise reach for mesh |
| **Traefik** | Go, K8s-native | Auto-discovery from K8s ingress; simple ops |
| **AWS API Gateway / GCP API Gateway / Azure APIM** | Managed | Cloud-locked but zero ops |

For Kotlin/Spring shops: **Spring Cloud Gateway** is the default. Routes as Kotlin DSL, integrates with Spring Security and observability stack.

### Spring Cloud Gateway example

```kotlin
@Configuration
class GatewayConfig {
    @Bean
    fun routes(builder: RouteLocatorBuilder): RouteLocator = builder.routes {
        route("orders") {
            path("/api/v1/orders/**")
            filters {
                addRequestHeader("X-Gateway", "spring-cloud-gateway")
                circuitBreaker { name = "ordersCB" }
                retry(3)
                requestRateLimiter {
                    rateLimiter = redisRateLimiter
                    keyResolver = principalNameResolver
                }
            }
            uri("lb://order-service")        // load-balanced URI (with discovery)
        }
        route("customers") {
            path("/api/v1/customers/**")
            uri("lb://customer-service")
        }
    }

    @Bean
    fun principalNameResolver(): KeyResolver = KeyResolver { exchange ->
        exchange.getPrincipal<Principal>()
            .map { it.name }
            .switchIfEmpty(Mono.just(exchange.request.remoteAddress?.address?.hostAddress ?: "anonymous"))
    }
}
```

The DSL is Kotlin-friendly. Routes are dynamic (can be reloaded via config server).

### Kong example (declarative)

```yaml
# kong.yaml
_format_version: "3.0"
services:
  - name: order-service
    url: http://order-service:8080
    routes:
      - paths: ["/api/v1/orders"]
    plugins:
      - name: jwt
      - name: rate-limiting
        config:
          minute: 100
          policy: local
      - name: prometheus
```

Plugin-driven. Add JWT validation, rate limiting, observability with config.

---

## 3. Gateway anti-patterns

- **Business logic in the gateway.** Should stay in services. Gateway is plumbing.
- **One huge gateway routing everything.** Single point of failure + bottleneck. Consider per-tenant / per-region gateways.
- **Auth at gateway only.** Defence in depth — services should also verify JWT/session. Trust no transitive auth.
- **Gateway as service mesh.** Different abstraction layer. Mesh handles service-to-service; gateway handles client-to-service.

---

## 4. Service Discovery

When ServiceA wants to call ServiceB, how does it find an instance of B?

| Method | How |
|---|---|
| **Static config** | URL in `application.yml`. Fine for very few services. |
| **DNS-based** | K8s native: `http://order-service.namespace.svc.cluster.local` resolves to a service IP that load-balances |
| **Client-side discovery** | Service registers in registry; client queries registry; client picks instance. (Eureka, Consul) |
| **Server-side discovery** | Service registers; load balancer at gateway picks instance. (K8s services, AWS ELB) |
| **Service mesh discovery** | Mesh proxy handles it transparently. (Istio with Envoy) |

### Eureka (client-side, Spring Cloud Netflix)

```kotlin
// build.gradle.kts
implementation("org.springframework.cloud:spring-cloud-starter-netflix-eureka-client")
```

```yaml
spring:
  application:
    name: order-service
eureka:
  client:
    service-url:
      defaultZone: http://eureka.internal:8761/eureka/
```

Service registers itself on startup; clients use load-balanced URI (`lb://order-service`). Spring Cloud LoadBalancer / Ribbon picks an instance.

### Consul (similar pattern, more general K-V + discovery)

```yaml
spring:
  cloud:
    consul:
      host: consul.internal
      port: 8500
      discovery:
        instance-id: ${spring.application.name}:${spring.cloud.client.ip-address}:${server.port}
```

### Kubernetes DNS (simplest if K8s)

```yaml
# K8s service
apiVersion: v1
kind: Service
metadata:
  name: order-service
spec:
  selector:
    app: order-service
  ports:
    - port: 8080
```

```kotlin
// In another service:
@Bean
fun orderClient() = WebClient.builder().baseUrl("http://order-service.assista.svc.cluster.local:8080").build()
```

**For K8s deployments: use K8s native DNS first.** Add Eureka/Consul only if you need features beyond DNS (health-aware load balancing, KV config, etc.).

---

## 5. Load balancing strategies

| Strategy | When |
|---|---|
| **Round-robin** | Default; uniform instances |
| **Least connections** | Long-lived connections vary |
| **Weighted** | Canary or shadow traffic |
| **Consistent hashing** | Session affinity, cache-locality |
| **Locality-aware** | Multi-zone clusters; prefer same-zone |

Spring Cloud LoadBalancer:

```kotlin
@Bean
fun loadBalancerSupplier(): ServiceInstanceListSupplier =
    ServiceInstanceListSupplier.builder()
        .withDiscoveryClient()
        .withRoundRobin()           // or withRandom, withZonePreference, etc.
        .build(...)
```

For more sophisticated routing (canary, latency-based) — that's mesh territory.

---

## 6. Service Mesh — what and when

A service mesh deploys a **sidecar proxy** alongside every service instance. All inter-service traffic flows through proxies (Envoy in Istio, Linkerd2-proxy in Linkerd).

The mesh transparently provides:
- **mTLS** between all services (auto-issued certs)
- **Load balancing** (advanced policies)
- **Retries / circuit breakers** at the network layer
- **Traffic shaping** (canary, percentage-based routing, mirroring)
- **Observability** (metrics + tracing for all inter-service calls)
- **Authorisation policies** (which services can talk to which)

### Istio vs Linkerd

| | Istio | Linkerd |
|---|---|---|
| Complexity | Heavy, many CRDs | Lightweight, fewer concepts |
| Performance | Envoy (C++); high resource use | Linkerd2-proxy (Rust); very low |
| Adoption | Larger ecosystem | Smaller but growing |
| Use case | Full-feature for complex orgs | Default for "I want mesh, not enterprise" |

**Default recommendation:** Linkerd for new adoption. Istio if you need its specific features (advanced routing, multi-cluster federation).

### When to adopt mesh

Adopt **when**:
- 10+ services with growing inter-service complexity
- mTLS required everywhere (compliance, zero-trust)
- Need fine-grained traffic shaping (canary by header, percentage)
- Observability gaps that mesh would fill

**Don't adopt when**:
- 3 services and a clear plan
- Team without K8s operational maturity
- You'd be adopting mesh to avoid writing one Resilience4j config

Mesh is operational complexity. Don't take it on for marginal benefits.

---

## 7. Gateway + Mesh interaction

```
Client → [Gateway] → [Service A] → mesh sidecar → [Service B] → mesh sidecar → [Service C]
              ↑                          ↑                       ↑
        North-South traffic           East-West traffic (mesh manages)
        (gateway manages)
```

- **Gateway** handles **client-to-service** (north-south)
- **Mesh** handles **service-to-service** (east-west)
- They overlap on routing/retry/circuit at the gateway entry — usually let gateway handle initial routing, mesh take over once inside the cluster.

Don't double-instrument. Pick one tool for each concern:
- **Auth**: gateway validates JWT; services trust the gateway's pre-validated header
- **Rate limit**: gateway for client-facing; mesh has built-in too
- **Circuit breaker**: mesh handles inter-service; library (Resilience4j) inside services for external API calls (not in mesh path)

---

## 8. Decision tree — what do you need

```
How many services?
│
├── 1   → No gateway, no discovery, no mesh. Use Spring Modulith.
│
├── 2-5
│   ├── Need single client entry point?   → Add gateway
│   ├── Need service-to-service discovery? → K8s DNS or Eureka
│   └── Mesh?  → No. Use Resilience4j in services.
│
├── 5-20
│   ├── Gateway: yes
│   ├── Discovery: K8s DNS or Consul
│   ├── Mesh: optional. Lean Linkerd if mTLS / advanced traffic.
│   └── Otherwise: Resilience4j + library-based observability
│
└── 20+
    ├── Gateway: yes, possibly per-domain
    ├── Mesh: probably yes (Istio or Linkerd)
    ├── Discovery: K8s native or Consul
    └── Observability: invest heavily (OTel collector, central tracing, central logs)
```

For `assista-platform` (currently Spring Modulith with 16 bounded contexts, no extraction yet):
- Gateway: not yet needed
- Discovery: not yet needed
- Mesh: definitely not yet

Pre-write the decision in your ADRs so the future split has a plan.

---

## 9. Gateway patterns

### Pattern: BFF (Backend for Frontend)

Different clients (web, mobile, partner API) have different needs. Instead of one gateway exposing everything, deploy per-client gateways:

```
Mobile app → [Mobile BFF] → [Service A, B, C]
Web app    → [Web BFF]    → [Service A, B, C]
Partner    → [Partner BFF] → [Service A, B, C with different auth]
```

Each BFF tailors the API surface to the client (aggregates calls, transforms shapes, applies different auth).

Trade-off: more deployables. Win: each client team owns their BFF without coupling to other clients.

### Pattern: Strangler at the gateway

When extracting a service from a monolith:

```
Step 1: Gateway routes all /api/* → monolith
Step 2: Build new service for /api/orders/*
Step 3: Gateway routes /api/orders/* → new service; rest still monolith
Step 4: Iterate
Step 5: Monolith dies when last route is moved
```

See `deploy-and-decomposition.md` for the full strangler pattern.

---

## 10. Common pitfalls

- **Gateway as single point of failure.** Multiple replicas always, with health-aware load balancing.
- **Gateway with no rate limit.** First abuse takes you down. Default: per-client quota.
- **Service discovery without health checks.** Dead instances stay in the registry → traffic to nothing.
- **Eureka with K8s.** Two discovery systems competing. Pick one.
- **Mesh deployed without ops capability.** Mesh adds debugging surface. Be sure team can handle it.
- **mTLS without certificate rotation.** Certs expire silently. Mesh should auto-rotate.
- **Gateway routes hard-coded.** Use a config server / database for dynamic routing.
- **Forgetting trace propagation through gateway.** W3C TraceContext headers must pass through; gateway shouldn't strip.
- **Gateway transformation as ETL.** Don't normalise data shapes at the gateway; it becomes app logic in the wrong place.
