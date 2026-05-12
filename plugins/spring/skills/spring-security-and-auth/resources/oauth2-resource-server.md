# OAuth2 Resource Server (JWT)

Your service receives JWTs issued by an external IdP (Keycloak, Auth0, Okta, Cognito), validates them, and authenticates requests.

This is the **most common modern auth pattern**.

---

## 1. The flow

```
1. Client logs in at IdP                  → receives JWT
2. Client calls your API with JWT          → Authorization: Bearer eyJhbGciOiJSUzI1NiIs…
3. Your service validates JWT
   - Signature (against IdP's JWK Set)
   - Expiry (`exp` claim)
   - Issuer (`iss` claim matches expected)
   - Audience (`aud` claim includes your service)
4. Build Authentication from JWT claims
5. Pass to controllers (with @PreAuthorize / @AuthenticationPrincipal Jwt)
```

You don't validate user credentials. The IdP does. You verify the IdP's signed token.

---

## 2. Minimum config

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://idp.example.com/realms/main
```

That single property:
- Discovers JWK set URI via OpenID Connect discovery (`<issuer-uri>/.well-known/openid-configuration`)
- Caches the JWKs
- Validates signature, `iss`, `exp`, `nbf`, `aud` for every incoming token
- Maps claims to `Authentication` via default converter

```kotlin
@Bean
fun securityFilterChain(http: HttpSecurity): SecurityFilterChain = http
    .authorizeHttpRequests { ... }
    .oauth2ResourceServer { it.jwt(Customizer.withDefaults()) }
    .build()
```

That's it. JWT auth in 4 lines of code.

---

## 3. JWT vs opaque tokens

| | JWT | Opaque token |
|---|---|---|
| Self-contained | Yes — claims encoded in token | No — server queries IdP for info |
| Validation | Offline (signature check + claim check) | Online (call IdP's introspection endpoint) |
| Revocation | Hard — token valid until expiry | Easy — IdP says revoked |
| Latency | Local | Adds IdP round-trip per request (cache!) |
| Size | Larger (~1KB) | Smaller (~30 bytes) |

**JWT for most cases**. Keep tokens short (5-15 min); use refresh token for renewal.

**Opaque for**:
- High-security needs (instant revocation)
- IdP doesn't expose JWKs
- Tokens carry sensitive data you don't want decoded client-side

Spring supports both:

```kotlin
// JWT
.oauth2ResourceServer { it.jwt() }

// Opaque
.oauth2ResourceServer { it.opaqueToken(Customizer.withDefaults()) }

// application.yml:
// spring.security.oauth2.resourceserver.opaquetoken.introspection-uri: https://idp/.../introspect
// spring.security.oauth2.resourceserver.opaquetoken.client-id: my-service
// spring.security.oauth2.resourceserver.opaquetoken.client-secret: ...
```

---

## 4. Custom JWT converter — extract roles / scopes

By default, Spring converts JWT `scope` claim → `SCOPE_*` authorities:

```
JWT: { "scope": "orders.read orders.write" }
↓
Authorities: ["SCOPE_orders.read", "SCOPE_orders.write"]
```

For Keycloak (uses `realm_access.roles` instead):

```kotlin
@Configuration
class JwtConfig {
    @Bean
    fun jwtAuthenticationConverter(): JwtAuthenticationConverter {
        val authoritiesConverter = JwtGrantedAuthoritiesConverter().apply {
            setAuthoritiesClaimName("scope")
            setAuthorityPrefix("SCOPE_")
        }
        val keycloakRolesConverter = Converter<Jwt, Collection<GrantedAuthority>> { jwt ->
            val realmAccess = jwt.getClaimAsMap("realm_access") ?: emptyMap()
            @Suppress("UNCHECKED_CAST")
            val roles = realmAccess["roles"] as? List<String> ?: emptyList()
            roles.map { SimpleGrantedAuthority("ROLE_$it") }
        }

        return JwtAuthenticationConverter().apply {
            setJwtGrantedAuthoritiesConverter { jwt ->
                authoritiesConverter.convert(jwt)!! + keycloakRolesConverter.convert(jwt)!!
            }
        }
    }
}

@Bean
fun securityFilterChain(http: HttpSecurity, jwtAuthConverter: JwtAuthenticationConverter): SecurityFilterChain = http
    .authorizeHttpRequests { ... }
    .oauth2ResourceServer { rs ->
        rs.jwt { jwt -> jwt.jwtAuthenticationConverter(jwtAuthConverter) }
    }
    .build()
```

Now `@PreAuthorize("hasRole('ADMIN')")` works alongside `hasAuthority('SCOPE_orders.write')`.

---

## 5. Audience validation

JWTs intended for **another** service shouldn't authorise yours. Validate `aud` claim:

```kotlin
@Bean
fun jwtDecoder(@Value("\${spring.security.oauth2.resourceserver.jwt.issuer-uri}") issuer: String): JwtDecoder {
    val decoder = JwtDecoders.fromIssuerLocation(issuer) as NimbusJwtDecoder

    val expectedAudience = "my-service-id"
    val validator = DelegatingOAuth2TokenValidator(
        JwtValidators.createDefaultWithIssuer(issuer),  // iss, exp, nbf
        JwtClaimValidator<List<String>>(JwtClaimNames.AUD) { aud ->
            aud != null && expectedAudience in aud
        },
    )
    decoder.setJwtValidator(validator)
    return decoder
}
```

Without audience validation: a token for `service-A` works on `service-B`. Cross-service privilege escalation.

---

## 6. Custom claim extraction

```kotlin
@RestController
class UserController {

    @GetMapping("/api/v1/me")
    fun me(@AuthenticationPrincipal jwt: Jwt): UserInfo {
        return UserInfo(
            subject = jwt.subject,                                       // "sub" claim
            email = jwt.getClaimAsString("email"),
            tenantId = jwt.getClaimAsString("tenant_id"),                // custom claim
            permissions = jwt.getClaimAsStringList("permissions") ?: emptyList(),
            issuedAt = jwt.issuedAt,
            expiresAt = jwt.expiresAt,
        )
    }
}
```

Add custom claims at IdP side (Keycloak mappers, Auth0 rules, etc.). Common ones:
- `tenant_id` — multi-tenant context
- `permissions` — finer-grained than scopes
- `org_id` — organisation membership
- `subscription_tier` — plan-based features

---

## 7. Token refresh handling

JWTs expire. Clients should refresh **before** expiry, not after a 401.

Server-side, you don't handle refresh — it's the client's job (call IdP's `/token` endpoint with `grant_type=refresh_token`). Your service just sees a fresh JWT.

If you return 401 with `WWW-Authenticate: Bearer error="invalid_token"`, well-behaved clients try refresh + retry.

---

## 8. Scopes vs roles vs permissions — terminology

OAuth2 vocabulary is overloaded. Pick one:

| Term | Usually means | Example |
|---|---|---|
| **Scope** | What an OAuth2 token is allowed to do | `orders.read`, `payments.write` |
| **Role** | A category of user in RBAC | `ADMIN`, `CUSTOMER`, `OPERATOR` |
| **Permission** | A fine-grained action | `order:cancel:any`, `user:delete:own` |
| **Authority** | Spring Security's generalisation | `SCOPE_orders.read` or `ROLE_ADMIN` |

Patterns:
- **Scope-only** — OAuth2 standard. Token scopes drive authorization. Simple, coarse.
- **Role-based** — `ROLE_*` claims. Easy mental model. Coarse-grained.
- **Permission-based (ABAC-ish)** — fine permissions per token. Flexible but complex.

For most APIs: scopes for cross-service, roles for human users, permissions for admin tools.

---

## 9. Performance: JWK caching

Spring Security caches the JWK Set after first fetch. Default TTL ~30 min.

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          # custom cache duration (Spring Security 6+)
          # via custom JwtDecoder bean — see below
```

For high-throughput services: pre-warm the JWKs cache on startup.

For multi-tenant with multiple issuers: see `multi-tenant-and-threats.md` §3.

---

## 10. Logout

JWTs can't be invalidated server-side without state. Options:

1. **Short-lived JWTs** (5-15 min) — "logout" effectively means waiting for expiry. Acceptable for most cases.
2. **Refresh token revocation** — IdP revokes refresh token; user can't get new access tokens. Existing access tokens valid until expiry.
3. **Token blacklist** — server-side store of revoked JWTs. Defeats the point of stateless JWT.
4. **JWT with version claim** — each user has a "token version" in DB; JWT carries it; mismatch = reject. Allows server-side revocation. Adds a DB hit per request (cacheable).

For most apps: short-lived tokens + refresh revocation suffices.

---

## 11. Testing OAuth2 Resource Server

```kotlin
@WebMvcTest(OrderController::class)
@Import(SecurityConfig::class)
class OrderControllerTest {

    @Autowired private lateinit var mvc: MockMvc

    @Test
    fun `GET orders requires SCOPE_orders read`() {
        mvc.get("/api/v1/orders")
            .andExpect { status { isUnauthorized() } }
    }

    @Test
    fun `with valid jwt + scope, allowed`() {
        mvc.get("/api/v1/orders") {
            with(SecurityMockMvcRequestPostProcessors.jwt()
                .jwt { jwt -> jwt
                    .subject("user-123")
                    .claim("scope", "orders.read")
                    .claim("tenant_id", "tenant-A")
                })
        }.andExpect { status { isOk() } }
    }
}
```

`SecurityMockMvcRequestPostProcessors.jwt()` lets you fake a JWT in tests without IdP integration. The Authentication is set as if a real JWT was validated.

For integration tests with real IdP: use Testcontainers + Keycloak image (heavy). Usually overkill — mock the JWT is enough.

---

## 12. Common errors

- **`InvalidBearerTokenException`** — wrong format, missing prefix `Bearer `, malformed JWT
- **`JwtException: Signed JWT rejected: Invalid signature`** — JWK mismatch (rotated key, wrong issuer)
- **`InvalidAudienceException`** — `aud` doesn't include expected value
- **`JwtExpiredException`** — token past `exp`
- **Empty authorities** — claim converter not extracting roles correctly

Configure the auth entry point to return useful `ProblemDetail` (see `spring-security-6-architecture.md` §10).

---

## 13. Anti-patterns

- **JWT in URL query params** (e.g. `?token=...`) — appears in logs, history, referer headers. Always `Authorization` header.
- **Storing JWT in localStorage** — XSS-readable. Use httpOnly cookies for browser clients (then it's CSRF-vulnerable instead — same-site lax + token-bound cookies mitigate).
- **Long-lived JWTs (hours/days)** — defeats purpose of stateless. Short access tokens + refresh tokens.
- **Multiple IdPs in one Spring service without explicit multi-tenancy** — token A can be valid for tenant B's resources. See `multi-tenant-and-threats.md`.
- **Trusting JWT claims without signature verification** — Spring does it by default; don't disable.
- **Custom JWT library** — `spring-boot-starter-oauth2-resource-server` does it. Use it.
- **Caching the validated `Authentication` object cross-request** — re-validate on every request unless you really know what you're doing.
