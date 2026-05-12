# Multi-Tenant Security and Threat Modeling

Tenant isolation patterns + OWASP API Top 10 + practical threat modeling for Spring services.

---

## 1. Multi-tenant isolation strategies

| Strategy | How | Operational cost | Isolation |
|---|---|---|---|
| **Shared everything (per-row `tenant_id`)** | Single DB, every table has `tenant_id`; queries filter by it | Lowest | Weakest (one bug = cross-tenant leak) |
| **Schema per tenant** | Each tenant has its own Postgres schema | Medium | Medium |
| **Database per tenant** | Each tenant has its own DB | Highest | Strongest (compliance / data residency) |

For SaaS: usually start with per-row, move to schema or DB if compliance demands.

### Per-row pattern (most common)

```kotlin
@Entity
@Table(name = "orders")
class OrderJpaEntity(
    @Id val id: UUID,
    @Column(name = "tenant_id", nullable = false)
    val tenantId: UUID,
    // …
)

interface OrderRepository : JpaRepository<OrderJpaEntity, UUID> {
    fun findByIdAndTenantId(id: UUID, tenantId: UUID): OrderJpaEntity?
    fun findAllByTenantId(tenantId: UUID): List<OrderJpaEntity>
}
```

**Discipline required:** every query filters by `tenant_id`. **Single missed filter = data leak.**

---

## 2. Tenant context propagation

The tenant ID comes from the authenticated user. Propagate explicitly through the call chain.

### Pattern A: ThreadLocal

```kotlin
object TenantContext {
    private val tenant = ThreadLocal<UUID>()
    fun set(tenantId: UUID) { tenant.set(tenantId) }
    fun current(): UUID = tenant.get() ?: error("no tenant context")
    fun clear() { tenant.remove() }
}

@Component
class TenantInterceptor : HandlerInterceptor {
    override fun preHandle(req: HttpServletRequest, res: HttpServletResponse, handler: Any): Boolean {
        val auth = SecurityContextHolder.getContext().authentication
        val tenantId = (auth as? JwtAuthenticationToken)?.token?.getClaimAsString("tenant_id")?.let(UUID::fromString)
            ?: return false.also { res.status = 401 }
        TenantContext.set(tenantId)
        return true
    }

    override fun afterCompletion(req: HttpServletRequest, res: HttpServletResponse, handler: Any, ex: Exception?) {
        TenantContext.clear()
    }
}

// Services use it:
@Service
class OrderService(private val orders: OrderRepository) {
    fun list(): List<Order> = orders.findAllByTenantId(TenantContext.current()).map { it.toDomain() }
}
```

**Pitfall:** ThreadLocal doesn't propagate to async work, coroutines, executors. Either explicitly pass tenant in async calls, or use `MdcCloseableScope` + `Context` propagation.

### Pattern B: Explicit parameter

```kotlin
@Service
class OrderService(private val orders: OrderRepository) {
    fun list(tenantId: TenantId): List<Order> = orders.findAllByTenantId(tenantId.value).map { it.toDomain() }
}

@RestController
class OrderController(private val service: OrderService) {
    @GetMapping("/orders")
    fun list(@AuthenticationPrincipal jwt: Jwt): List<OrderResponse> {
        val tenantId = TenantId(UUID.fromString(jwt.getClaimAsString("tenant_id")!!))
        return service.list(tenantId).map { it.toResponse() }
    }
}
```

More verbose; impossible to forget. **Preferred** for hot paths.

---

## 3. PostgreSQL Row-Level Security (RLS) — defense in depth

App-level filtering can be forgotten. RLS makes the DB enforce.

```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON orders
    FOR ALL
    USING (tenant_id = current_setting('app.tenant_id')::uuid);
```

Set the GUC per request via Spring:

```kotlin
@Component
class TenantRlsInterceptor(private val jdbc: JdbcTemplate) : HandlerInterceptor {

    override fun preHandle(req: HttpServletRequest, res: HttpServletResponse, handler: Any): Boolean {
        val tenantId = TenantContext.current()
        jdbc.execute("SET LOCAL app.tenant_id = '$tenantId'")
        return true
    }
}
```

Now even if app forgets `WHERE tenant_id = ?`, the DB enforces. Belt **and** suspenders.

Caveats:
- Affects performance (~5-10%)
- Superuser bypass — `BYPASSRLS` role. Application user should not have it.
- Doesn't help if app uses dynamic SQL that explicitly bypasses RLS.

---

## 4. Multi-tenant JWT considerations

If multiple tenants use the same IdP:
- `tenant_id` claim in JWT (custom)
- Validate at every request

If each tenant has its **own IdP** (rare, enterprise):
- Multi-issuer setup — Spring 6+ supports `JwtIssuerAuthenticationManagerResolver`:

```kotlin
@Bean
fun authManagerResolver(): JwtIssuerAuthenticationManagerResolver =
    JwtIssuerAuthenticationManagerResolver.fromTrustedIssuers(
        "https://tenant-a.example.com/realms/main",
        "https://tenant-b.example.com/realms/main",
    )

@Bean
fun securityFilterChain(http: HttpSecurity, resolver: JwtIssuerAuthenticationManagerResolver): SecurityFilterChain = http
    .oauth2ResourceServer { it.authenticationManagerResolver(resolver) }
    .build()
```

---

## 5. OWASP API Top 10 — quick review

Reference: [OWASP API Security Top 10 (2023)](https://owasp.org/API-Security/editions/2023/en/0x11-t10/).

### API1:2023 — Broken Object Level Authorization

> Attacker manipulates IDs to access objects they shouldn't.

**Example:** `GET /api/orders/123` works for any user, regardless of order ownership.

**Mitigation:**
- Always check ownership: `@PreAuthorize("@orderSecurity.isOwner(#id, authentication)")` or service-level check
- Use unguessable IDs (UUID, not sequential ints)
- Multi-tenant: filter by `tenant_id` in **every** query

### API2:2023 — Broken Authentication

> Weak / missing authentication on endpoints.

**Example:** Forgotten `permitAll()` on a sensitive endpoint. JWT validation disabled in dev profile and accidentally enabled in prod.

**Mitigation:**
- `anyRequest().authenticated()` as the catch-all
- Default deny; explicit allow-list for public endpoints
- Test auth on every endpoint (Spring Security test slice)

### API3:2023 — Broken Object Property Level Authorization

> User can read or modify properties they shouldn't.

**Example:** `PATCH /api/users/{id}` accepts any field including `role`. User upgrades themselves to admin.

**Mitigation:**
- Explicit DTOs at the boundary — `UserUpdateRequest` has only `name`, `email`. No `role`, no `password`.
- Never bind directly from `@RequestBody Map<String, Any>`
- Never use entities as request bodies

### API4:2023 — Unrestricted Resource Consumption

> No rate limits → attacker can DOS.

**Mitigation:**
- Rate limit (Bucket4j + Redis, see `api-design-principles/references/rest-best-practices.md`)
- Per-IP, per-API-key, per-user
- Cap payload sizes (`spring.servlet.multipart.max-file-size`)
- Cap query result sets (max page size 100, not unlimited)

### API5:2023 — Broken Function Level Authorization

> User reaches admin endpoints because of weak URL-level checks.

**Example:** `/api/admin/users` only checks `authenticated()`, not `hasRole('ADMIN')`.

**Mitigation:**
- Method-level `@PreAuthorize` in addition to URL config
- Audit every endpoint's authorization

### API6:2023 — Unrestricted Access to Sensitive Business Flows

> Attacker abuses business flows (mass account creation, ticket scalping).

**Mitigation:**
- Captcha / proof of work on sensitive flows
- Rate limit per business action, not just per endpoint
- Anomaly detection on unusual patterns

### API7:2023 — Server-Side Request Forgery (SSRF)

> User-supplied URL is fetched by your server.

**Example:** `POST /api/webhooks { url: "http://localhost:..." }`. Attacker reads internal services.

**Mitigation:**
- Validate URLs strictly — only public DNS, not localhost / private IPs
- Use deny-list (no `169.254.*`, `localhost`, `127.*`, `10.*`)
- Outbound calls via egress proxy that enforces rules

### API8:2023 — Security Misconfiguration

> Defaults left in place, dev configs in prod, missing security headers.

**Mitigation:**
- Apply security headers (see `spring-security-6-architecture.md` §8)
- No verbose error messages in prod (`server.error.include-stacktrace: never`)
- Disable Actuator endpoints that leak (`env`, `heapdump`, `loggers`)
- Run security review (Anthropic `/security-review`) before each major release

### API9:2023 — Improper Inventory Management

> Old / undocumented API versions still running, no monitoring.

**Mitigation:**
- API versioning (`/api/v1/...` deprecated → `/api/v2/...`)
- Sunset old versions explicitly
- Audit endpoint list periodically

### API10:2023 — Unsafe Consumption of APIs

> Trusting external APIs' data without validation.

**Example:** External webhook payload assumed safe; SQL injection through embedded fields.

**Mitigation:**
- Validate external input as untrusted (`@Valid`, sanitisation)
- Sign + verify webhooks (HMAC of payload)
- Limit external API response size to avoid memory issues

---

## 6. Threat modeling — STRIDE quick pass

For each component / data flow in your design, ask:

| | Threat | Example for an API |
|---|---|---|
| **S** Spoofing | Pretending to be someone else | Forged JWT, replay attack |
| **T** Tampering | Modifying data in flight | MITM (mitigated by HTTPS), forged request body |
| **R** Repudiation | Denying action | "I didn't make that payment" — mitigated by audit log + signed receipts |
| **I** Information disclosure | Reading data you shouldn't | API4 (over-fetch), error leaks (stack traces) |
| **D** Denial of service | Making service unavailable | No rate limits, expensive endpoints |
| **E** Elevation of privilege | User getting admin rights | API3 (mass assignment), forgotten auth check |

Walk through each component in your system, fill the cells. The empty cells need mitigation.

---

## 7. Security headers checklist

```yaml
.headers {
    it.contentTypeOptions { }                                            # X-Content-Type-Options: nosniff
    it.frameOptions { f -> f.deny() }                                    # X-Frame-Options: DENY
    it.httpStrictTransportSecurity { hsts ->
        hsts.maxAgeInSeconds(31_536_000).includeSubDomains(true).preload(true)
    }                                                                     # Strict-Transport-Security
    it.contentSecurityPolicy { csp ->
        csp.policyDirectives("default-src 'self'; frame-ancestors 'none'")
    }
    it.referrerPolicy { rp -> rp.policy(STRICT_ORIGIN_WHEN_CROSS_ORIGIN) }
    it.permissionsPolicy { pp -> pp.policy("camera=(), microphone=(), geolocation=()") }
}
```

For REST APIs, also:
- No HTML responses ever → no XSS concern in your own responses
- But responses go to browsers (your SPA); CSP / X-Frame-Options still matter

---

## 8. Audit logging — what and how

Every security-sensitive operation should leave a trail:

| Event | What to log |
|---|---|
| Authentication success / failure | Who, when, from where (IP), method |
| Authorization denial | Who, what they tried, why denied |
| Role / permission change | Who changed, who was affected, before/after |
| Sensitive data access | Who, what, when (for compliance) |
| Password reset / 2FA disable | Who initiated, when |
| Admin action | Who, what, with what argument |

Store separately from app logs (different retention, different access). Use structured logging:

```kotlin
log.info("AUDIT action={} actor={} target={} success={} ip={}",
    "order.cancel", auth.name, orderId, true, request.remoteAddr)
```

Or dedicated audit table / Kafka topic for compliance-grade audit trails.

**Don't log:**
- Passwords / tokens / secrets
- Full request bodies that may contain PII

---

## 9. Secret management

Hierarchy of where secrets live, from worst to best:

1. **Hardcoded in code** — ❌ never
2. **Plain config file in git** — ❌ never
3. **Plain env var (set by deployment script)** — ⚠️ minimum for non-prod
4. **K8s Secret (mounted file or env)** — ✅ baseline
5. **Vault / AWS Secrets Manager** — ✅ better for rotation
6. **Vault + just-in-time / dynamic secrets** — ✅ best for high-security

Rotation:
- Long-lived service credentials: rotate at least yearly
- API keys: support rotation (dual-key window)
- Certificates: automated via cert-manager / mesh

---

## 10. Dependencies — supply chain security

JVM dependencies have CVEs. Audit:

```bash
./gradlew dependencyCheckAnalyze    # OWASP Dependency Check
```

Or use:
- **Snyk** / **Dependabot** for automated PRs
- **Trivy** for container scanning

Pin versions; don't use `+` or `latest`. Review transitive deps on major upgrades.

---

## 11. Pre-deployment security review checklist

Before going to prod:

- [ ] `anyRequest().authenticated()` (or explicit `permitAll` only for known public)
- [ ] JWT validation with audience check
- [ ] `@PreAuthorize` on sensitive service methods
- [ ] No secrets in code / git / Docker image
- [ ] Security headers configured
- [ ] Rate limiting in place
- [ ] CORS limited to known origins
- [ ] Audit logging for security-sensitive ops
- [ ] Multi-tenant filter in every query (or RLS)
- [ ] Error messages don't leak stack traces
- [ ] Actuator endpoints secured (`management.endpoints.web.exposure.include` limited)
- [ ] Dependency vulnerabilities scanned
- [ ] Penetration test or `/security-review` passed
- [ ] Threat model documented
- [ ] Incident response runbook exists

---

## 12. Tools

- **Spring Security 6** — the framework
- **springdoc-openapi** — documents auth requirements in OpenAPI
- **Bucket4j-Redis** — distributed rate limiting
- **OWASP ZAP** — automated security scan
- **Snyk / Trivy** — dependency vulnerability scan
- **Vault / AWS Secrets Manager** — secret storage
- **HashiCorp Boundary / Pomerium** — zero-trust access (advanced)
- **OPA** — policy engine for complex ABAC
- **Anthropic `/security-review`** — review of code changes

Security is a continuous practice. This skill gives you the vocabulary. Pair with `/security-review` and threat modelling sessions for real-world application.
