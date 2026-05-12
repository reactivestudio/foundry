# Service-to-Service Authentication

Backend services calling each other within your platform. Not user auth.

---

## 1. The problem

When `service-A` calls `service-B`, how does `service-B` know:
1. The caller is `service-A`, not a random attacker?
2. (Optionally) On behalf of which user? (federated identity)

Three common patterns: shared secrets (avoid), mTLS, JWT-based.

---

## 2. mTLS (Mutual TLS) — service mesh's friend

Both sides present X.509 certificates. Trust based on PKI.

```
service-A presents client cert
              │
              ▼
service-B verifies cert against trusted CA
              │
              ▼
service-B reads subject DN: "CN=service-a.prod.example.com"
              │
              ▼
service-B knows caller identity, applies authorization
```

### Spring Security config

```kotlin
@Bean
fun securityFilterChain(http: HttpSecurity): SecurityFilterChain = http
    .authorizeHttpRequests {
        it.anyRequest().authenticated()
    }
    .x509 { x ->
        x.subjectPrincipalRegex("CN=(.*?)(?:,|$)")    // extract service name from CN
            .userDetailsService(serviceUserDetailsService)
    }
    .build()

@Bean
fun serviceUserDetailsService(): UserDetailsService = UserDetailsService { name ->
    User.withUsername(name)
        .authorities(serviceAuthorities(name))    // load authorities by service name
        .password("")
        .build()
}
```

### Where mTLS lives

- **Service mesh (Istio, Linkerd, Consul Connect)** — handles mTLS transparently. Pods get sidecar proxies. Auth happens at the proxy. App sees plain HTTP.
- **Direct mTLS** — apps handle TLS themselves. More complex; less common.

For Kubernetes deployments, **service mesh** is the right answer. Off the shelf.

### Pros

- Strong identity guarantee (PKI)
- No app-level credentials to manage
- Service mesh handles rotation automatically

### Cons

- Certificate management complexity
- Requires PKI infrastructure (mesh provides, or CA you run)
- Doesn't naturally carry user context

---

## 3. JWT propagation (federated identity)

User logs in once at the gateway / first service. JWT propagates through subsequent service calls.

```
User → Gateway → service-A → service-B → service-C
                ↓             ↓             ↓
              JWT₁          JWT₁         JWT₁
              (or)          (or)          (or)
              JWT₂          JWT₂         JWT₂
              (re-issued)
```

Two flavours:

### A. Pass-through JWT

Each service receives the user's original JWT (from the gateway).

```kotlin
// Outbound call propagates incoming JWT
@RestController
class ServiceAController(private val restClient: RestClient) {

    @GetMapping("/api/v1/aggregate")
    fun aggregate(@AuthenticationPrincipal jwt: Jwt): AggregateResponse {
        val rawJwt = jwt.tokenValue
        val serviceB = restClient.get()
            .uri("https://service-b.internal/api/v1/data")
            .header("Authorization", "Bearer $rawJwt")
            .retrieve()
            .body(ServiceBResponse::class.java)
        ...
    }
}
```

Pros: simple, each service sees user's identity.
Cons: token scope often too broad for inter-service; cross-service trust = leaks to leak everywhere.

### B. Token exchange (per-service tokens)

Each service requests its own narrower token from the IdP (OAuth2 token exchange — RFC 8693).

```kotlin
// Service-A receives user's JWT, exchanges for a service-B-scoped JWT
fun exchangeToken(userJwt: String, targetAudience: String): String {
    val response = restClient.post()
        .uri("https://idp.example.com/token")
        .body(LinkedMultiValueMap<String, String>().apply {
            add("grant_type", "urn:ietf:params:oauth:grant-type:token-exchange")
            add("subject_token", userJwt)
            add("subject_token_type", "urn:ietf:params:oauth:token-type:access_token")
            add("audience", targetAudience)
        })
        .retrieve()
        .body(TokenResponse::class.java)
    return response.accessToken
}
```

Pros: principle of least privilege; revoking one service's exchanged token doesn't kill the user session.
Cons: extra IdP round-trips per cross-service call; need IdP support for token exchange.

### Hybrid

- mTLS authenticates **service identity** (mesh-level)
- JWT carries **user identity** (app-level)
- Both checked in service B: "service-A authenticates via mTLS, on behalf of user X (from JWT)"

Common pattern in mature setups.

---

## 4. Client Credentials flow (no user context)

For service-to-service where there's no user (cron jobs, internal API calls):

```
service-A → IdP (token endpoint with client_id + client_secret)
            ↓
            JWT for service-A
            ↓
service-A → service-B (with Authorization: Bearer ...)
```

Spring Security has a `ClientCredentials` flow:

```kotlin
@Bean
fun authorizedClientManager(
    clientRegistrations: ClientRegistrationRepository,
    authorizedClients: OAuth2AuthorizedClientService,
): OAuth2AuthorizedClientManager {
    val provider = OAuth2AuthorizedClientProviderBuilder.builder()
        .clientCredentials()
        .build()
    return AuthorizedClientServiceOAuth2AuthorizedClientManager(clientRegistrations, authorizedClients)
        .apply { setAuthorizedClientProvider(provider) }
}

@Service
class ServiceBClient(
    private val manager: OAuth2AuthorizedClientManager,
    private val restClient: RestClient,
) {
    fun callServiceB(): ServiceBResponse {
        val authorizedClient = manager.authorize(
            OAuth2AuthorizeRequest.withClientRegistrationId("service-b-client")
                .principal("system")
                .build()
        )!!
        return restClient.get()
            .uri("https://service-b.internal/api/v1/data")
            .header("Authorization", "Bearer ${authorizedClient.accessToken.tokenValue}")
            .retrieve()
            .body(ServiceBResponse::class.java)!!
    }
}
```

```yaml
spring:
  security:
    oauth2:
      client:
        registration:
          service-b-client:
            client-id: service-a
            client-secret: ${SERVICE_A_CLIENT_SECRET}
            authorization-grant-type: client_credentials
            scope: service-b.read
        provider:
          ...
```

Spring handles token caching, refresh, expiry.

---

## 5. API key auth — simple but limited

`X-API-Key: ak_xxx`

Pros: dead simple, no IdP needed.
Cons: keys are bearer tokens (anyone with the key can use it); no rotation policy; flat permission model.

Use for:
- Webhook receivers
- Customer-supplied integration tokens
- Internal-only services where complexity isn't worth it

Implementation:

```kotlin
@Component
class ApiKeyAuthFilter(private val keyStore: ApiKeyStore) : OncePerRequestFilter() {

    override fun doFilterInternal(req: HttpServletRequest, res: HttpServletResponse, chain: FilterChain) {
        val apiKey = req.getHeader("X-API-Key")
        if (apiKey != null) {
            val client = keyStore.findByKey(apiKey)
            if (client != null && !client.isRevoked) {
                val auth = UsernamePasswordAuthenticationToken(
                    client.name,
                    null,
                    client.authorities.map { SimpleGrantedAuthority(it) },
                )
                SecurityContextHolder.getContext().authentication = auth
            }
        }
        chain.doFilter(req, res)
    }
}

@Bean
fun securityFilterChain(http: HttpSecurity, apiKeyFilter: ApiKeyAuthFilter): SecurityFilterChain = http
    .addFilterBefore(apiKeyFilter, BearerTokenAuthenticationFilter::class.java)
    .authorizeHttpRequests { it.anyRequest().authenticated() }
    .build()
```

Store keys hashed (bcrypt) in DB, not plaintext. Same as passwords.

---

## 6. Trust model — defense in depth

In production, layer:

```
┌────────────────────────────────────────────────────────┐
│  Network (VPC / private subnet)                         │  ← only internal traffic possible
├────────────────────────────────────────────────────────┤
│  Service mesh / mTLS                                    │  ← service identity guaranteed
├────────────────────────────────────────────────────────┤
│  Application JWT validation                             │  ← user identity + scopes
├────────────────────────────────────────────────────────┤
│  Method-level @PreAuthorize                             │  ← fine-grained authorization
├────────────────────────────────────────────────────────┤
│  Database row-level security                            │  ← last-line tenant isolation
└────────────────────────────────────────────────────────┘
```

Each layer fails open if removed. Together: deep defense.

For low-criticality internal services: network + mTLS might suffice. For payment-critical: all five.

---

## 7. Outbound auth — calling external APIs

When your service calls an external API (Stripe, GitHub, Slack):

### API key
Most common. Store in vault. `Authorization: Bearer <key>` or `X-API-Key`.

### OAuth2 client credentials
For organisation-level access. Each external API has its own dance.

### Per-user OAuth2 (3-legged)
User authorises your app to access their data. Tokens stored per-user. Spring OAuth2 Client supports this.

```kotlin
@Configuration
class ExternalApisConfig {

    @Bean
    fun githubClient(): GithubClient = GithubClient(
        token = System.getenv("GITHUB_TOKEN")
            ?: error("GITHUB_TOKEN required"),
    )
}
```

### Secret rotation
External API keys should rotate. Easiest pattern: secret manager + restart on rotation.

For high-volume keys with strict rotation: dual-key (old + new both accepted for migration window).

---

## 8. Idempotency for service-to-service

Network is unreliable. Caller retries. Receiver should be idempotent.

Standard pattern: `Idempotency-Key` header (UUID per logical operation).

```kotlin
@PostMapping("/api/v1/charges")
fun charge(
    @RequestHeader("Idempotency-Key") idempotencyKey: String,
    @RequestBody req: ChargeRequest,
): ChargeResponse {
    return idempotencyService.executeOnce(idempotencyKey) {
        chargeService.charge(req)
    }
}
```

See `cqrs-implementation/resources/write-side-patterns.md` §6 for the full pattern.

---

## 9. Service-to-service in `assista-platform`

Per CLAUDE.md, this is a Spring Modulith monolith with cross-module communication via:
- **In-process events** — no network, no auth check (modules trust each other)
- **`contract/` package** — shared types

When (if) modules split into services:
- mTLS between services via mesh
- JWT for user identity propagation
- Per-service IdP client for client credentials when no user is involved
- Same `contract/` package becomes the published event schema for Kafka

---

## 10. Anti-patterns

- **Hardcoded credentials in code / config files in git** — always env vars or secret manager
- **Same JWT for user-facing and internal-only flows** — narrow scope per use
- **Shared service tokens** ("we have one token for all internal calls") — can't revoke, can't audit
- **mTLS without rotation** — keys silently expire; cert rotation is operational must
- **Trusting `X-Forwarded-For` for IP-based access** — header is forgeable. Use only behind trusted reverse proxies.
- **No timeouts on outbound calls** — slow downstream takes down your service
- **Not propagating trace IDs** — debugging cross-service issues becomes guesswork
