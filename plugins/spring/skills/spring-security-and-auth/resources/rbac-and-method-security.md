# RBAC and Method Security

`@PreAuthorize`, `@PostAuthorize`, custom expression evaluators, attribute-based access control (ABAC).

---

## 1. Enable method security

```kotlin
@Configuration
@EnableMethodSecurity   // required for @PreAuthorize to work
class SecurityConfig
```

Without `@EnableMethodSecurity`, `@PreAuthorize` is **silently ignored**. Common mistake.

---

## 2. `@PreAuthorize` — the workhorse

Evaluated **before** the method executes. If `false`, throws `AccessDeniedException` → 403.

```kotlin
@RestController
@RequestMapping("/api/v1/orders")
class OrderController(private val service: OrderService) {

    @PreAuthorize("hasAuthority('SCOPE_orders.read')")
    @GetMapping
    fun list(): List<OrderResponse> = service.findAll()

    @PreAuthorize("hasAuthority('SCOPE_orders.write')")
    @PostMapping
    fun create(@Valid @RequestBody req: CreateOrderRequest): OrderResponse = service.create(req)

    @PreAuthorize("hasRole('ADMIN') or @orderSecurity.isOwner(#id, authentication)")
    @DeleteMapping("/{id}")
    fun delete(@PathVariable id: UUID) = service.delete(id)
}
```

### Expression syntax

| Expression | Meaning |
|---|---|
| `hasAuthority('X')` | Checks for the literal authority `X` |
| `hasAnyAuthority('A', 'B')` | At least one of |
| `hasRole('USER')` | Checks for `ROLE_USER` (auto-prefixed) |
| `hasAnyRole('USER', 'ADMIN')` | At least one of (auto-prefixed) |
| `authenticated()` | Anyone logged in |
| `permitAll()` | Anyone, including anonymous |
| `denyAll()` | Nobody |
| `isAnonymous()` | Only unauthenticated |
| `principal.username == 'alice'` | Spring Expression Language access |
| `@beanName.method(args)` | Call a bean method (powerful) |
| `#paramName` | Reference method parameter |

---

## 3. `@PostAuthorize` — check the return value

Run after method, decide on return:

```kotlin
@PostAuthorize("returnObject.ownerId == authentication.name or hasRole('ADMIN')")
@GetMapping("/{id}")
fun get(@PathVariable id: UUID): OrderResponse = service.findById(id)
```

If the order's owner doesn't match the authenticated user, throw 403.

Used for "read your own data or be admin" patterns where ownership is determined at query time.

**Caveat**: the method **runs** before the check. For costly operations or operations with side effects, prefer `@PreAuthorize` with a custom check.

---

## 4. Method parameters in expressions

```kotlin
@PreAuthorize("#userId == authentication.name")
@GetMapping("/users/{userId}/private")
fun privateInfo(@PathVariable userId: String): PrivateInfo = ...
```

`#userId` references the method parameter. Allows access only if the user is asking about themselves.

---

## 5. Custom security expressions

When expressions get complex, extract to a bean:

```kotlin
@Component("orderSecurity")
class OrderSecurityExpressions(private val orders: OrderRepository) {

    fun isOwner(orderId: UUID, authentication: Authentication): Boolean {
        val order = orders.findById(orderId).orElse(null) ?: return false
        return order.customerId.toString() == authentication.name
    }

    fun canAccessOrders(customerId: UUID, authentication: Authentication): Boolean {
        return customerId.toString() == authentication.name
            || hasAuthority(authentication, "SCOPE_orders.admin")
    }

    private fun hasAuthority(auth: Authentication, authority: String): Boolean =
        auth.authorities.any { it.authority == authority }
}

@RestController
class OrderController {
    @PreAuthorize("@orderSecurity.isOwner(#id, authentication)")
    @GetMapping("/{id}")
    fun get(@PathVariable id: UUID) = ...
}
```

Three benefits:
1. Testable: `OrderSecurityExpressions` is a plain Spring bean
2. Reusable across controllers
3. Stays out of controller code

---

## 6. Filtering collections — `@PostFilter`

```kotlin
@PostFilter("filterObject.ownerId == authentication.name or hasRole('ADMIN')")
@GetMapping
fun list(): List<OrderResponse> = service.findAll()
```

Filters the returned `List`. Only orders the user owns are returned.

**Caveat**: loads everything from DB, then filters in memory. **Slow** at scale. Prefer query-time filtering:

```kotlin
@GetMapping
fun list(@AuthenticationPrincipal jwt: Jwt): List<OrderResponse> =
    service.findOwnedBy(jwt.subject)
```

---

## 7. RBAC hierarchies

Define role inheritance via `RoleHierarchy`:

```kotlin
@Configuration
class RoleHierarchyConfig {

    @Bean
    fun roleHierarchy(): RoleHierarchy = RoleHierarchyImpl().apply {
        setHierarchy("""
            ROLE_SUPERADMIN > ROLE_ADMIN
            ROLE_ADMIN > ROLE_USER
            ROLE_USER > ROLE_GUEST
        """.trimIndent())
    }

    @Bean
    fun expressionHandler(roleHierarchy: RoleHierarchy): MethodSecurityExpressionHandler {
        return DefaultMethodSecurityExpressionHandler().apply { setRoleHierarchy(roleHierarchy) }
    }
}
```

Now `hasRole('USER')` returns true for `ROLE_USER`, `ROLE_ADMIN`, and `ROLE_SUPERADMIN`.

**Caveat**: deep hierarchies hide what permissions actually grant access. Keep flat or 2 levels max.

---

## 8. ABAC — attribute-based access control

Beyond roles: decisions based on attributes of subject, resource, action, context.

```kotlin
@Component("abac")
class AttributeBasedAccess(
    private val resources: ResourceRepository,
    private val org: OrgRepository,
) {

    fun canAccess(resourceId: UUID, authentication: Authentication): Boolean {
        val resource = resources.findById(resourceId).orElse(null) ?: return false
        val userTenantId = (authentication as? JwtAuthenticationToken)?.token?.getClaimAsString("tenant_id")
            ?: return false

        // Attribute: same tenant
        if (resource.tenantId != userTenantId) return false

        // Attribute: same org
        val userOrgId = (authentication.token).getClaimAsString("org_id") ?: return false
        if (resource.orgId != userOrgId) return false

        // Attribute: not archived (unless admin)
        if (resource.isArchived && !authentication.authorities.any { it.authority == "ROLE_ADMIN" }) return false

        return true
    }
}

// Usage
@PreAuthorize("@abac.canAccess(#id, authentication)")
@GetMapping("/resources/{id}")
fun get(@PathVariable id: UUID): ResourceResponse = ...
```

ABAC scales beyond what RBAC handles cleanly when:
- Multi-tenant context matters
- Attributes (sensitivity, ownership, time-of-day) drive decisions
- Per-resource permissions

For complex ABAC, dedicated policy engines (OPA — Open Policy Agent) externalise the rules. Spring just calls `opa.evaluate(...)`.

---

## 9. Combining `@PreAuthorize` with filter-chain rules

`SecurityFilterChain.authorizeHttpRequests` controls **broad** URL-level access. `@PreAuthorize` controls **method-level** detail.

```kotlin
.authorizeHttpRequests {
    it.requestMatchers("/api/v1/orders/**").authenticated()  // any authenticated user can reach
}

// Then in controller:
@PreAuthorize("hasAuthority('SCOPE_orders.read')")
@GetMapping("/api/v1/orders/{id}")
fun get(...) { ... }
```

The filter chain says "must be authenticated to reach this URL." `@PreAuthorize` says "must have orders.read to call this method."

Defense in depth. The filter chain catches "no auth at all"; `@PreAuthorize` catches "wrong scope."

---

## 10. Service-layer security (recommended)

Best practice: `@PreAuthorize` on **service** methods, not just controllers.

```kotlin
@Service
class OrderService(...) {

    @PreAuthorize("hasAuthority('SCOPE_orders.read')")
    fun findById(id: OrderId): Order? = ...

    @PreAuthorize("hasAuthority('SCOPE_orders.write')")
    fun create(req: CreateOrderRequest): Order = ...

    @PreAuthorize("@orderSecurity.isOwner(#id, authentication) or hasRole('ADMIN')")
    fun cancel(id: OrderId, reason: String) = ...
}
```

Why service layer:
- Internal callers (other services, scheduled jobs, event listeners) hit the same check
- Controller can compose multiple service calls; each enforces its own auth

Where it conflicts:
- Internal calls without authentication (e.g., from `@Scheduled` job) — provide a system principal via `RunAsManager` or special internal interface
- Performance — auth check overhead on every method (~µs)

For internal-only methods, mark as `protected` / `internal` or provide a separate non-annotated method:

```kotlin
@Service
class OrderService(...) {

    @PreAuthorize("...")
    fun create(req: CreateOrderRequest): Order = createInternal(req)

    /** Internal callers (events, jobs). Bypasses auth check. */
    fun createInternal(req: CreateOrderRequest): Order { ... }
}
```

---

## 11. Testing method security

```kotlin
@SpringBootTest
@ActiveProfiles("test")
class OrderServiceSecurityTest {

    @Autowired private lateinit var orderService: OrderService

    @Test
    fun `findById requires SCOPE orders read`() {
        assertThatThrownBy { orderService.findById(OrderId.random()) }
            .isInstanceOf(AuthenticationCredentialsNotFoundException::class.java)
    }

    @Test
    @WithMockUser(authorities = ["SCOPE_orders.read"])
    fun `with scope, findById works`() {
        // Inside @WithMockUser, SecurityContext has the mock principal
        assertThat(orderService.findById(OrderId.random())).isNull()
    }

    @Test
    @WithMockUser(authorities = ["SCOPE_other"])
    fun `with wrong scope, denied`() {
        assertThatThrownBy { orderService.findById(OrderId.random()) }
            .isInstanceOf(AccessDeniedException::class.java)
    }
}
```

`@WithMockUser` sets up a fake authentication. `@WithMockJwt` (custom annotation) for JWT-specific tests.

---

## 12. Audit-logging authorization decisions

For sensitive operations, log who did what:

```kotlin
@Component
class AuditingAspect(private val log: AuditLog) {

    @Around("@annotation(Audited)")
    fun audit(joinPoint: ProceedingJoinPoint): Any? {
        val auth = SecurityContextHolder.getContext().authentication
        val methodName = joinPoint.signature.toShortString()
        val args = joinPoint.args.joinToString { it.toString() }

        try {
            val result = joinPoint.proceed()
            log.success(actor = auth.name, action = methodName, args = args)
            return result
        } catch (e: AccessDeniedException) {
            log.denied(actor = auth.name, action = methodName, args = args, reason = e.message)
            throw e
        } catch (e: Exception) {
            log.error(actor = auth.name, action = methodName, args = args, error = e)
            throw e
        }
    }
}

// Usage
@Audited
@PreAuthorize("...")
fun deleteUser(id: UUID) { ... }
```

Cross-cutting via AOP (see `spring-boot-mastery/resources/bean-lifecycle-and-aop.md` §9).

---

## 13. Anti-patterns

- **`@Secured("...")` instead of `@PreAuthorize`** — `@Secured` is older, less powerful. Always `@PreAuthorize`.
- **`@PreAuthorize` only on controllers** — bypassed by direct service calls. Put on service.
- **SpEL too complex** — extract to bean. `@PreAuthorize("...")` 5+ lines is unreadable.
- **`@PostFilter` for large collections** — DB-side filtering instead.
- **Role hierarchy 5 levels deep** — collapse to 2-3.
- **Caching authorization decisions** — leaks across users. Cache lookups (which authorities does user X have?), not decisions.
- **Hardcoded permission strings** — typo = silent allow. Use constants: `object Permissions { const val ORDERS_WRITE = "SCOPE_orders.write" }`.
