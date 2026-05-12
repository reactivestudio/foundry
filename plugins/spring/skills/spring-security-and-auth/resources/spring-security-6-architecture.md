# Spring Security 6 Architecture

The mental model: filter chain, authentication, authorization, exception handling. Modern config (no `WebSecurityConfigurerAdapter`).

---

## 1. The filter chain

Spring Security inserts a chain of `Filter`s into the servlet pipeline. Each does one thing:

```
HTTP Request
   │
   ▼
┌─────────────────────────────────────┐
│  CorsFilter                          │  ← CORS preflight + headers
├─────────────────────────────────────┤
│  CsrfFilter                          │  ← CSRF token check (disabled for JWT APIs)
├─────────────────────────────────────┤
│  LogoutFilter                        │  ← /logout endpoint
├─────────────────────────────────────┤
│  BearerTokenAuthenticationFilter     │  ← parses Authorization: Bearer …
├─────────────────────────────────────┤
│  ExceptionTranslationFilter          │  ← turns AuthN/AuthZ exceptions into 401/403
├─────────────────────────────────────┤
│  AuthorizationFilter                 │  ← enforces authorizeHttpRequests rules
└─────────────────┬───────────────────┘
                  ▼
         DispatcherServlet
                  ▼
            Controller
```

You configure which filters and in what shape via a single `SecurityFilterChain` bean.

---

## 2. The `SecurityFilterChain` bean (modern config)

In Spring Security 6, `WebSecurityConfigurerAdapter` is **removed**. The replacement: declare a `SecurityFilterChain` bean.

```kotlin
@Configuration
@EnableWebSecurity
class SecurityConfig {

    @Bean
    fun securityFilterChain(http: HttpSecurity): SecurityFilterChain = http
        .authorizeHttpRequests { auth ->
            auth.requestMatchers("/actuator/health/**", "/actuator/info").permitAll()
            auth.requestMatchers(HttpMethod.GET, "/api/v1/public/**").permitAll()
            auth.requestMatchers("/api/v1/admin/**").hasAuthority("SCOPE_admin")
            auth.anyRequest().authenticated()
        }
        .oauth2ResourceServer { it.jwt(Customizer.withDefaults()) }
        .csrf { it.disable() }
        .sessionManagement { it.sessionCreationPolicy(SessionCreationPolicy.STATELESS) }
        .headers {
            it.frameOptions { f -> f.deny() }
            it.contentSecurityPolicy { csp -> csp.policyDirectives("default-src 'self'") }
            it.httpStrictTransportSecurity { hsts -> hsts.maxAgeInSeconds(31_536_000).includeSubDomains(true) }
        }
        .exceptionHandling { ex ->
            ex.authenticationEntryPoint { _, response, _ ->
                response.status = 401
                response.contentType = "application/problem+json"
                response.writer.write("""{"type":"https://errors.example.com/unauthenticated","title":"Unauthenticated","status":401}""")
            }
            ex.accessDeniedHandler { _, response, _ ->
                response.status = 403
                response.contentType = "application/problem+json"
                response.writer.write("""{"type":"https://errors.example.com/forbidden","title":"Forbidden","status":403}""")
            }
        }
        .build()
}
```

The lambda-based DSL is the canonical modern style.

---

## 3. Authentication vs Authorization

Two distinct concerns. Don't conflate.

| | **Authentication** | **Authorization** |
|---|---|---|
| Question | Who are you? | What can you do? |
| Result | A `Principal` / `Authentication` object | Decision: allow or deny |
| Failure HTTP | 401 Unauthorized | 403 Forbidden |
| Where | Authentication filter | `authorizeHttpRequests` rules + `@PreAuthorize` |

**Misuse pattern**: returning 403 when no auth was provided. Correct: 401 ("not authenticated"). 403 means "I know who you are, but you can't do this."

`ExceptionTranslationFilter` handles this — make sure you map exceptions consistently.

---

## 4. Authentication mechanisms

| Mechanism | When | Spring support |
|---|---|---|
| **JWT (Bearer token)** | Most modern APIs | `oauth2ResourceServer.jwt()` |
| **Opaque token + introspection** | When IdP doesn't expose JWKs, or revocation matters | `oauth2ResourceServer.opaqueToken()` |
| **Session cookie** | Browser-only apps | `formLogin()` |
| **API key** (`X-API-Key`) | Server-to-server, simple | Custom filter |
| **mTLS** | Service-to-service in mesh | `x509()` |
| **HTTP Basic** | Quick admin endpoints only | `httpBasic()` |

For new services consumed by web/mobile/internal: JWT via OAuth2 Resource Server. Covered in `oauth2-resource-server.md`.

---

## 5. Authorization expressions

Three levels of URL-based authorization:

```kotlin
.authorizeHttpRequests {
    // By role / authority
    it.requestMatchers("/admin/**").hasRole("ADMIN")                  // checks for "ROLE_ADMIN"
    it.requestMatchers("/api/orders/**").hasAuthority("SCOPE_orders") // raw authority match

    // By HTTP method + path
    it.requestMatchers(HttpMethod.GET, "/api/public/**").permitAll()
    it.requestMatchers(HttpMethod.POST, "/api/orders").authenticated()

    // By IP
    it.requestMatchers("/internal/**").access(WebExpressionAuthorizationManager(
        "hasIpAddress('10.0.0.0/8') and hasAuthority('SCOPE_internal')"
    ))

    // Custom rule
    it.requestMatchers("/api/payments/**").access(
        AuthorizationManager { auth, _ ->
            AuthorizationDecision(auth.get().authorities.any { it.authority == "SCOPE_payments" })
        }
    )

    it.anyRequest().authenticated()    // default deny
}
```

### `hasRole` vs `hasAuthority`

- `hasRole("ADMIN")` checks for authority `"ROLE_ADMIN"` — auto-prefixed
- `hasAuthority("ROLE_ADMIN")` checks for the literal string `"ROLE_ADMIN"`
- `hasAuthority("SCOPE_orders")` checks for `"SCOPE_orders"` (OAuth2 scope, no auto-prefix)

Use whatever the IdP issues. Most OAuth2 IdPs use scopes (`SCOPE_*`). RBAC systems use roles (`ROLE_*`). Be consistent.

---

## 6. CSRF

Cross-Site Request Forgery: attacker tricks a logged-in user's browser into making a request the user didn't intend.

**Stateful (cookie-based session):** CSRF matters. Spring's default protection works.

**Stateless (JWT in Authorization header):** CSRF doesn't apply — attacker can't read the JWT from localStorage / cookie without XSS, and `Authorization` header isn't auto-sent cross-origin. Disable:

```kotlin
.csrf { it.disable() }
.sessionManagement { it.sessionCreationPolicy(SessionCreationPolicy.STATELESS) }
```

**Hybrid (httpOnly cookie + Bearer):** CSRF still relevant. Use SameSite cookies + CSRF token.

---

## 7. CORS

Cross-Origin Resource Sharing — who can call this API from a browser?

```kotlin
@Configuration
class CorsConfig : WebMvcConfigurer {
    override fun addCorsMappings(registry: CorsRegistry) {
        registry.addMapping("/api/**")
            .allowedOrigins("https://app.example.com", "https://admin.example.com")
            .allowedMethods("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
            .allowedHeaders("*")
            .allowCredentials(true)
            .maxAge(3600)
    }
}
```

**Pitfalls:**
- `allowedOrigins("*")` + `allowCredentials(true)` — Spring rejects this combo (browsers do too)
- `allowedOriginPatterns("https://*.example.com")` for wildcard subdomains
- Configure CORS for `/api/**` only; don't allow cross-origin for `/actuator/**`

---

## 8. Security headers

Defaults are good in Spring Security 6, but verify:

| Header | Purpose | Spring default |
|---|---|---|
| `X-Content-Type-Options: nosniff` | Prevent MIME-sniff | Yes |
| `X-Frame-Options: DENY` | Prevent clickjacking | Yes |
| `Strict-Transport-Security` | Force HTTPS | Configure explicitly |
| `Content-Security-Policy` | XSS mitigation | Configure explicitly |
| `Cross-Origin-Opener-Policy` | Isolation | Configure for modern security |
| `Referrer-Policy` | Privacy | Configure |

```kotlin
.headers {
    it.contentSecurityPolicy { csp -> csp.policyDirectives("default-src 'self'") }
    it.httpStrictTransportSecurity { hsts ->
        hsts.maxAgeInSeconds(31_536_000).includeSubDomains(true).preload(true)
    }
    it.referrerPolicy { rp -> rp.policy(ReferrerPolicy.STRICT_ORIGIN_WHEN_CROSS_ORIGIN) }
}
```

---

## 9. Reading the current authenticated user

```kotlin
@RestController
class UserController {

    @GetMapping("/api/v1/me")
    fun me(): UserInfo {
        val auth = SecurityContextHolder.getContext().authentication
            ?: throw IllegalStateException("must be authenticated to reach here")

        return UserInfo(
            subject = auth.name,
            authorities = auth.authorities.map { it.authority },
            principal = auth.principal,
        )
    }

    // Or use @AuthenticationPrincipal:
    @GetMapping("/api/v1/me-v2")
    fun meV2(@AuthenticationPrincipal jwt: Jwt): UserInfo =
        UserInfo(
            subject = jwt.subject,
            authorities = jwt.getClaimAsStringList("authorities") ?: emptyList(),
            principal = jwt.claims,
        )
}
```

`SecurityContextHolder.getContext().authentication` works anywhere; `@AuthenticationPrincipal` is the controller-friendly version.

---

## 10. Exception handling — proper 401 / 403 mapping

The default Spring Security responses are HTML / plain text. For a REST API, you want `ProblemDetail`:

```kotlin
.exceptionHandling { ex ->
    ex.authenticationEntryPoint(JsonAuthenticationEntryPoint())
    ex.accessDeniedHandler(JsonAccessDeniedHandler())
}

class JsonAuthenticationEntryPoint : AuthenticationEntryPoint {
    override fun commence(request: HttpServletRequest, response: HttpServletResponse, authException: AuthenticationException) {
        val problem = ProblemDetail.forStatusAndDetail(HttpStatus.UNAUTHORIZED, "Authentication required").apply {
            type = URI.create("https://errors.example.com/unauthenticated")
            title = "Unauthenticated"
            instance = URI.create(request.requestURI)
        }
        response.status = 401
        response.contentType = "application/problem+json"
        response.writer.write(ObjectMapper().writeValueAsString(problem))
    }
}

class JsonAccessDeniedHandler : AccessDeniedHandler {
    override fun handle(request: HttpServletRequest, response: HttpServletResponse, accessDeniedException: AccessDeniedException) {
        val problem = ProblemDetail.forStatusAndDetail(HttpStatus.FORBIDDEN, "Access denied").apply {
            type = URI.create("https://errors.example.com/forbidden")
            title = "Forbidden"
            instance = URI.create(request.requestURI)
        }
        response.status = 403
        response.contentType = "application/problem+json"
        response.writer.write(ObjectMapper().writeValueAsString(problem))
    }
}
```

Consistent error envelope across REST API.

---

## 11. Testing with Spring Security

```kotlin
@WebMvcTest(OrderController::class)
@Import(SecurityConfig::class)
class OrderControllerSecurityTest {

    @Autowired private lateinit var mvc: MockMvc

    @Test
    fun `GET orders requires auth`() {
        mvc.get("/api/v1/orders").andExpect { status { isUnauthorized() } }
    }

    @Test
    @WithMockUser(authorities = ["SCOPE_orders.read"])
    fun `GET orders allowed with scope`() {
        mvc.get("/api/v1/orders").andExpect { status { isOk() } }
    }

    @Test
    fun `POST orders with valid JWT works`() {
        mvc.post("/api/v1/orders") {
            with(SecurityMockMvcRequestPostProcessors.jwt()
                .jwt { jwt -> jwt.claim("scope", "orders.write") })
            contentType = MediaType.APPLICATION_JSON
            content = """{"customerId":"..."}"""
        }.andExpect { status { isCreated() } }
    }
}
```

Spring Security Test provides `@WithMockUser` for simple cases and `SecurityMockMvcRequestPostProcessors.jwt()` for JWT-based testing.

See `testing-strategy-kotlin-spring/resources/spring-boot-testing.md` for the slice setup.

---

## 12. Pitfalls

- **Configuring auth at filter level only** — bypassed if you have multiple controllers. Add method-level `@PreAuthorize`.
- **Using `permitAll()` to debug** and forgetting to revert. Always check before merge.
- **CSRF disabled but session-based** — vulnerable. Either fully stateless + JWT or full CSRF.
- **CORS too permissive** — `allowedOrigins("*")` in production. Set explicit origins.
- **Forgetting `@EnableMethodSecurity`** — `@PreAuthorize` annotations silently ignored.
- **Mixing custom auth filters with OAuth2 Resource Server config** — order issues; only one auth filter should run per request.
- **Path matching pitfalls** — `requestMatchers("/api/users")` doesn't match `/api/users/`. Use `/api/users/**` for tree.
- **Caching pre-auth fetches** — caching authorization decisions cross-request leaks data. Cache **expensive lookups** (user roles), not **authorization decisions**.
