# Practices — bounded contexts & context mapping

Code shapes for the patterns and anti-patterns named in SKILL.md. Examples use Kotlin syntax but no Kotlin-specific idioms — read them as you would any typed OO language.

## 1. Naming collision → two contexts

### Bad — one `User` does double duty

```kotlin
// One BC, one User class — but the class carries two unrelated concerns.
class User(
    val id: UUID,
    val email: String,
    val passwordHash: String,        // Identity concern
    val billingAddress: Address,     // Billing concern
    val invoices: List<Invoice>,     // Billing concern
    val lastLoginAt: Instant         // Identity concern
)
```

Same word means two things: login subject *and* party-with-invoices. A feature added on one side risks breaking the other; product debates become "which `User` do we mean?".

### Good — two contexts, two models, explicit reference

```kotlin
// Identity context
package com.example.identity
class User(
    val id: UserId,
    val email: Email,
    val passwordHash: PasswordHash,
    val lastLoginAt: Instant
)

// Billing context
package com.example.billing
class Customer(
    val id: CustomerId,
    val identityRef: UserId,         // a reference, not a copy
    val billingAddress: Address,
    val invoices: List<Invoice>
)
```

Two contexts; two languages; each model is self-consistent. The `UserId` crossing the boundary is a value, never an `identity.User` instance.

## 2. ACL — leaking vs sealed

### Bad — vendor types in the domain

```kotlin
// domain package
import com.stripe.model.Customer        // domain importing vendor SDK
import com.stripe.model.PaymentMethod

class CheckoutService(private val stripe: Stripe) {
    fun checkout(orderId: OrderId, stripeCustomerId: String) {
        val customer: Customer = stripe.customers.retrieve(stripeCustomerId)
        // domain logic operating on Stripe.Customer ...
    }
}
```

`Stripe.Customer` is now a domain type by accident. A vendor SDK upgrade can break compilation in the heart of the domain.

### Good — sealed ACL, domain sees only its own types

```kotlin
// domain — no vendor imports
package com.example.checkout.domain
interface PaymentGateway {
    fun charge(amount: Money, customer: CustomerRef): ChargeResult
}

// ACL — adapter + translator
package com.example.checkout.infrastructure.stripe
import com.stripe.Stripe
import com.stripe.model.Charge as StripeCharge

class StripePaymentGateway(private val client: StripeClient) : PaymentGateway {
    override fun charge(amount: Money, customer: CustomerRef): ChargeResult {
        val request = translateOutbound(amount, customer)
        val stripeCharge: StripeCharge = client.charges.create(request)
        return translateInbound(stripeCharge)            // never returns StripeCharge
    }
    private fun translateOutbound(amount: Money, customer: CustomerRef): ChargeRequest { /*…*/ }
    private fun translateInbound(charge: StripeCharge): ChargeResult { /*…*/ }
}
```

The domain depends only on `PaymentGateway`. Vendor types are quarantined to the ACL package.

## 3. OHS + Published Language — versioned contract

### Bad — internal entity as the wire schema

```kotlin
@RestController
class OrderController(private val orders: OrderRepository) {
    @GetMapping("/orders/{id}")
    fun get(@PathVariable id: String): Order = orders.findById(OrderId(id))
    // returns the internal aggregate — fields downstream consumers shouldn't see,
    // every consumer coupled to internal model evolution.
}
```

Adding a private field renames a JSON field. Every downstream breaks at once.

### Good — published schema, internal model evolves separately

```kotlin
// contract/ — versioned, published
package com.example.orders.contract.v1
class OrderV1(
    val orderId: String,
    val status: String,           // documented enum
    val totalAmount: Long,        // cents, documented
    val placedAt: String          // ISO-8601
)

// Internal aggregate evolves freely; controller translates to the published shape.
@RestController
class OrderController(private val orders: OrderRepository) {
    @GetMapping("/orders/{id}")
    fun get(@PathVariable id: String): OrderV1 =
        orders.findById(OrderId(id)).toV1()
}
```

The internal `Order` evolves; `OrderV1` is the stable published contract. A breaking schema change requires `OrderV2`, not silent mutation.

## 4. Shared Kernel — drift vs governance

### Bad — kernel grows silently

A `shared-kernel` module starts with three value objects. Six months later:

```
shared-kernel/
├── Money.kt
├── Currency.kt
├── EmailAddress.kt
├── OrderStatus.kt            ← Orders-context concept leaked here
├── InvoiceStatus.kt          ← Billing-context concept leaked here
├── CustomerSegmentation.kt   ← Sales-context concept leaked here
└── ... 35 more
```

The kernel is no longer kernel; it's an undisclosed Big Ball of Mud. Every release coordinates across three teams.

### Good — small, governed, justified

```kotlin
// shared-kernel — stays small; entries are invariants both contexts genuinely hold.
class Money(val amount: Long, val currency: Currency) { /* canonical math */ }

class EmailAddress private constructor(val value: String) {
    companion object { fun of(raw: String): EmailAddress { /* validation */ } }
}
```

Every addition requires both owners to sign off. Status enums and segmentation models live in *their own* contexts.

## 5. Conformist trap

### Bad — domain entity speaks vendor

```kotlin
class Repository(
    val ghId: Long,
    val ghOwnerLogin: String,
    val ghDefaultBranch: String,
    val ghVisibility: String        // "public" | "private" | "internal" — GitHub's enum
)
```

The domain's `Repository` is now defined by GitHub's vocabulary. Switching to GitLab requires a domain-wide rename; the language is foreign to non-GitHub-aware engineers reading the code.

### Good — domain language; ACL translates

```kotlin
class Repository(
    val id: RepositoryId,
    val owner: OwnerHandle,
    val defaultBranch: BranchName,
    val visibility: Visibility       // domain enum: Public / Private / Internal
)

class GitHubRepositoryAdapter(private val client: GitHubClient) : RepositoryGateway {
    override fun fetch(handle: OwnerHandle, name: RepoName): Repository {
        val gh = client.getRepository("$handle/$name")
        return Repository(
            id = RepositoryId(gh.id),
            owner = OwnerHandle(gh.ownerName),
            defaultBranch = BranchName(gh.defaultBranch),
            visibility = translateVisibility(gh.visibility)
        )
    }
}
```

The domain reads naturally without knowing the vendor; the ACL absorbs vendor vocabulary.

## 6. Separate Ways — declared

### Bad — accidental non-integration

Two teams build "their own" customer tables. Six months later: three sources of truth, periodic reconciliation jobs, and a chat channel called `#why-do-customers-differ`.

### Good — declared on the context map

> **Marketing CRM ↔ Operations Tools**: Separate Ways. No integration. Operations does not consume CRM data; CRM does not consume Operations data. If a future use case demands cross-context data, an ACL or OHS edge is introduced *then*.

Documented, with the reason: "duplication cost < integration cost given current use cases; re-evaluate next quarter."

## Review checklist

When reviewing a BC design or context map:

- Each edge labeled with one of the 9 patterns? Un-labeled edges hide a Conformist or Big Ball of Mud.
- Each vendor / legacy upstream has an ACL? Search domain packages for vendor SDK imports — should return nothing.
- Outbound calls translate too? Search for domain types appearing as arguments to vendor SDK calls.
- Shared Kernel < ~10 classes and stable? Growth signals drift.
- Published Language versioned (`v1`, `v2` in package or schema)? Or are we mutating the same shape silently?
- The map lives in the repo, not someone's head?
