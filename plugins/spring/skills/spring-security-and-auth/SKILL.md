---
name: spring-security-and-auth
description: "Spring Security 6 architecture for Kotlin services — Security filter chain, OAuth2 Resource Server with JWT, RBAC via `@PreAuthorize` and method security, service-to-service authentication (mTLS, JWT propagation), multi-tenant security, threat modeling (OWASP API Top 10). Use when designing or hardening auth in a Spring service, integrating an identity provider, or implementing fine-grained authorization."
risk: safe
source: "custom — Spring Security 6 for Kotlin services"
date_added: "2026-05-12"
---

# Spring Security & Auth (Kotlin / Spring Boot 3+)

Spring Security 6 is opinionated, powerful, and frequently misused. This skill: the mental model, the modern (post-`WebSecurityConfigurerAdapter`) configuration, OAuth2 Resource Server (the most common pattern), method-level RBAC, service-to-service auth, multi-tenancy, and threat modeling.

> Security is a property of the system, not a layer. But for a Spring service, 80% of practical security lives in the SecurityFilterChain and method security.

## Use this skill when

- Designing auth for a new Spring service
- Migrating from Spring Security 5 to 6 (`WebSecurityConfigurerAdapter` removed)
- Integrating with an external OAuth2 / OIDC provider (Keycloak, Auth0, Okta, Cognito)
- Implementing JWT validation, custom claims, scope-based authorization
- Adding RBAC with `@PreAuthorize` or attribute-based access control
- Designing service-to-service trust (mTLS, JWT propagation)
- Multi-tenant security (tenant isolation)
- Threat-modeling an API surface

## Do not use this skill when

- You need **building blocks of REST APIs** without auth specifics — use `api-design-principles`
- The task is **architectural** in scope (decide auth strategy at system level) — pair this with `system-design-fundamentals`
- You need a **full security audit** of a running system — use Anthropic `/security-review`
- The auth requirement is "block all by default" with no users — Spring Security gives that out of the box; you don't need this skill

## Selective Reading Rule

| File | Description | When to read |
|---|---|---|
| `resources/spring-security-6-architecture.md` | Filter chain, `SecurityFilterChain` bean (no more `WebSecurityConfigurerAdapter`), authentication vs authorization, exception handling | Setting up Spring Security, understanding why a request gets a 401 vs 403 |
| `resources/oauth2-resource-server.md` | JWT validation, JWKs, JWT vs opaque tokens, custom claims, scope-based authorization, token introspection | Service consumes JWTs from external IdP |
| `resources/rbac-and-method-security.md` | `@PreAuthorize` / `@PostAuthorize` / `@Secured`, role hierarchies, custom expression evaluator, ABAC patterns | Per-method authorization, fine-grained access |
| `resources/service-to-service-auth.md` | mTLS for backend-to-backend, JWT propagation (federated identity), service accounts, client credentials flow | Designing auth between your own services |
| `resources/multi-tenant-and-threats.md` | Tenant isolation patterns (per-row, per-schema, per-DB), tenant context propagation, OWASP API Top 10 review | Multi-tenant SaaS; threat modelling an API |

## The mental model

Spring Security is a **filter chain** that runs before your controllers. Each filter does one thing:

```
Request → [CSRF] → [CORS] → [Authentication] → [Authorization] → [Headers] → ... → Controller
```

You configure which filters run and how via a `SecurityFilterChain` bean. Most apps need:

1. **Authentication** — who is this request from?
2. **Authorization** — is this principal allowed to do this?
3. **Sensible defaults** — CSRF, CORS, security headers

90% of Spring Security setups are: "validate JWT from `Authorization: Bearer ...` header, then enforce `@PreAuthorize` rules on controllers."

## Core principles

1. **Default deny.** All endpoints require auth except an explicit allow-list (`/actuator/health`, `/login`, etc.).
2. **Validate at the boundary.** JWT validation, signature check, expiry, audience — at the filter, not in business logic.
3. **Authorization in code, not config.** `@PreAuthorize` close to the method; not a giant config block. Easier to review.
4. **Audit security-sensitive operations.** Login, role change, password reset, admin actions — emit auditable events.
5. **Defense in depth.** Don't rely on one layer. Multiple checks: filter validates token, method validates scope, DB row-level security validates tenant.
6. **Don't roll your own crypto / hash / JWT parsing.** Use established libraries (Spring Security, Nimbus JOSE, jjwt). The bugs you write will be the ones you don't catch.
7. **Treat secrets as code's runtime input.** Env vars, secret managers, mounted files. Never in the repo.

## The standard architecture (90% of services)

```
                ┌────────────────────────────────────┐
                │   External IdP (Keycloak / Okta)    │  ← issues JWTs
                └──────────────┬─────────────────────┘
                               │ JWT
                ┌──────────────▼─────────────────────┐
                │   Your Spring Service               │
                │   ┌──────────────────────────────┐ │
                │   │ OAuth2 Resource Server Filter│ │  ← validates JWT signature, expiry, audience
                │   ├──────────────────────────────┤ │
                │   │ SecurityFilterChain          │ │  ← URL-level authorization
                │   ├──────────────────────────────┤ │
                │   │ Method Security              │ │  ← @PreAuthorize per method
                │   └──────────────────────────────┘ │
                └────────────────────────────────────┘
```

If you have this, you have 90% of what most backend services need. The skill's resource files dive into each layer.

## Default configuration template

```kotlin
@Configuration
@EnableWebSecurity
@EnableMethodSecurity   // for @PreAuthorize on @Service methods
class SecurityConfig {

    @Bean
    fun securityFilterChain(http: HttpSecurity): SecurityFilterChain = http
        .authorizeHttpRequests {
            it.requestMatchers("/actuator/health/**").permitAll()
            it.requestMatchers("/actuator/info").permitAll()
            it.requestMatchers(HttpMethod.GET, "/api/v1/public/**").permitAll()
            it.anyRequest().authenticated()                       // default deny
        }
        .oauth2ResourceServer { it.jwt(Customizer.withDefaults()) }
        .csrf { it.disable() }                                    // stateless API
        .sessionManagement { it.sessionCreationPolicy(SessionCreationPolicy.STATELESS) }
        .headers {
            it.frameOptions { f -> f.deny() }
            it.contentSecurityPolicy { csp -> csp.policyDirectives("default-src 'self'") }
        }
        .build()
}
```

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://idp.example.com/realms/main
          # or for static keys: jwk-set-uri: https://.../.well-known/jwks.json
```

Spring auto-loads the JWK set, validates signatures, parses claims into an `Authentication` object accessible via `SecurityContextHolder`.

## Top anti-patterns

- **`WebSecurityConfigurerAdapter`** — removed in Security 6. Use `SecurityFilterChain` bean.
- **`http.authorizeRequests()`** — deprecated. Use `http.authorizeHttpRequests()`.
- **CSRF enabled on stateless REST APIs** — defaults are designed for browser sessions; disable for JWT APIs.
- **`hasRole("ROLE_USER")`** — Spring auto-prefixes; use `hasRole("USER")`. Inconsistency is a footgun.
- **Custom JWT parsing** — use `oauth2ResourceServer.jwt()`. Don't write your own.
- **Storing JWT in localStorage on frontend** — XSS-readable. Use httpOnly cookies for browser clients.
- **Long-lived JWTs** — JWTs can't be revoked easily. Keep them short (5-15 min), refresh tokens for longer.
- **Plaintext passwords anywhere** — bcrypt/argon2. Spring's `BCryptPasswordEncoder` is the default.

## Related skills

- `api-design-principles` — error format (`ProblemDetail`), 401 vs 403 semantics, idempotency
- `spring-boot-mastery` — configuration, profiles
- `system-design-fundamentals` — auth at architectural scale (gateway, service mesh)
- `testing-strategy-kotlin-spring` — Spring Security test slices, `@WithMockUser`
- `architecture-decision-records` — document auth decisions
- Anthropic `/security-review` — verify changes don't introduce vulnerabilities

## Limitations

- Patterns focus on Spring Security 6 + Spring Boot 3+. Older versions (5.x and below) have different APIs.
- Doesn't cover **identity provider implementation** (running your own Keycloak / building OIDC server). Use an external IdP for production.
- Cryptographic details (hash algorithms, key rotation procedures) require security expertise beyond this skill.
- Compliance (GDPR, PCI-DSS, HIPAA) is mentioned but not covered in depth — engage compliance specialists.
- Stop and ask if **threat model** is unclear: who are the attackers, what are the assets, what compliance applies.
