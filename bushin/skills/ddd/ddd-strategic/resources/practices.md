# Practices — bad / good pairs

Three pairs, each illustrating one strategic decision. Kotlin syntax for familiarity; basic features only (`data class`, nullables, primitives) — strategic DDD is language-agnostic.

## 1. Context violation — one entity, three meanings

**Bad** — a single `Customer` shared by Identity, Billing, and Support:

```kotlin
data class Customer(
    val id: UUID,
    val email: String,
    val passwordHash: String?,     // null outside Identity
    val creditLimit: BigDecimal?,  // null outside Billing
    val supportTier: String?,      // null outside Support
    val billingAddress: Address?,
    val lastLoginAt: Instant?,
    // ...keeps growing as each team adds fields
)
```

Smell: **nullable-soup** encoding "Customer means three different things in three different contexts." Each team defensively null-checks the others' fields; cross-team changes ripple unnecessarily.

**Good** — three context-owned models, joined by ID across contexts:

```kotlin
// Identity BC
data class User(val id: UUID, val email: String, val passwordHash: String)

// Billing BC
data class Account(val id: UUID, val creditLimit: BigDecimal, val billingAddress: Address)

// Support BC
data class Contact(val id: UUID, val email: String, val tier: SupportTier)
```

Same person, three context-complete models. No nullables encoding "this field isn't mine". Cross-context joins by ID; if Billing needs the email, it asks Identity (or copies the stable subset it needs).

## 2. Core / Generic confusion — building the commodity, not the moat

**Bad** — logistics SaaS where route optimization is the differentiator, but the team has spent six months on auth:

```kotlin
// 4000 lines: password hashing, MFA, SSO/SAML, token rotation, session stores
class AuthService(/* 12 collaborators */) { /* six engineer-months */ }

// Meanwhile…
class RouteOptimizer { fun optimize(stops: List<Stop>): Route = stops.toRoute() }  // 50 lines, naive
```

Smell: **Generic built in-house**, Core under-invested. Auth0 / Keycloak / Cognito cover 95% of auth out of the box. The six months on auth are six months *not* spent on the actual moat.

**Good** — Generic outsourced, Core gets the depth:

```kotlin
// Generic — thin adapter around a vendor
class AuthAdapter(private val auth0: Auth0Client) { /* 200 lines of translation */ }

// Core — the moat
class RouteOptimizer(
    private val trafficForecaster: TrafficForecaster,
    private val driverProfiles: DriverProfileStore,
    private val solver: ConstraintSolver,
) {
    fun optimize(stops: List<Stop>, fleet: Fleet, window: TimeWindow): Route { /* real iteration */ }
}
```

Investment ratio matches the strategic stakes.

## 3. Premature context split — boundaries drawn by schema

**Bad** — two BCs along the relational split (`orders` table vs `order_lines` table), each owned by a different team:

```kotlin
// "OrdersContext" — Team Alpha
class OrderService { fun placeOrder(customerId: UUID): OrderId }

// "OrderLinesContext" — Team Beta, separate repo
class OrderLineService { fun addLine(orderId: OrderId, sku: Sku, qty: Int) }
```

Smell: **data-driven boundary**. The schema has two tables, so somebody drew two contexts. But "an order is its lines, atomically" is one invariant. Teams now coordinate every release; their refactors block each other.

**Good** — one BC owning the invariant:

```kotlin
// Checkout BC — one team, one transactional boundary
class OrderPlacement {
    fun place(cart: Cart, payment: PaymentMethod): OrderId   // order + lines atomically
}
```

Boundary follows the *capability* (placing an order), not the *schema* (which tables it touches). One team, one invariant, one BC.
