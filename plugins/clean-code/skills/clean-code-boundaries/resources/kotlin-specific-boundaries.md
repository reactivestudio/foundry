# Kotlin-Specific Boundary Idioms

Kotlin changes some of what Martin's chapter argued. This file is what Kotlin does *for* you at boundaries, what it does *not* do, and the idioms that replace Java-era ceremony.

## Read-only `Map` / `List` — half of the chapter's `Map` argument is already handled

Martin's worry about `Map.clear()` is real in Java, where there is one `Map` interface and every reference can mutate it. Kotlin splits the interface:

| Kotlin type | Mutation methods? | Notes |
|---|---|---|
| `Map<K, V>` | **No** — read-only view | `clear()`, `put()`, etc. don't compile. |
| `MutableMap<K, V>` | Yes | Use only inside the class that owns the data. |
| Same split for `List`, `Set`, `Collection`. | | |

So this Kotlin signature is already safe against the original chapter complaint:

```kotlin
fun sensors(): Map<SensorId, Sensor>      // caller cannot clear() / put()
```

**But the encapsulation argument still stands.** Even with a read-only view, you've published the *shape* `Map<SensorId, Sensor>`:

- Caller depends on `sensorMap[id]` (lookup by key). If you switch storage to a list of records sorted by `id`, every caller breaks.
- Caller can hand the `Map` to other callers — the boundary type has escaped into code you didn't write.
- You've committed `SensorId` and `Sensor` to be the public key/value pair forever.

The right move is usually still to wrap and expose verbs (`byId(id): Sensor?`, `register(sensor)`), not nouns. **Read-only views shrink the blast radius; they don't replace the seam.**

## The `typealias` trap — *not* a wrapper

A common mistake: assuming `typealias` creates a type boundary.

```kotlin
// ✗ This is NOT a boundary
typealias OrderId = String

fun process(orderId: OrderId) { ... }   // still accepts any String
val raw = "lol"
process(raw)                             // compiles fine — typealias is an alias, not a type
```

`typealias` is a compile-time alias for documentation. The compiler treats `OrderId` and `String` as the same type.

If you want real type safety at the seam:

```kotlin
// ✓ Real wrapping — typed at compile time, zero runtime cost
@JvmInline
value class OrderId(val value: String) {
    init { require(value.isNotBlank()) { "OrderId cannot be blank" } }
}

fun process(orderId: OrderId) { ... }
process("lol")        // ✗ does not compile
process(OrderId("ord_42"))   // ✓
```

**House rule.** Use `@JvmInline value class` for boundary IDs and other thin wrappers. Use `typealias` only for shortening long generic signatures (`typealias UserRow = Pair<UserEntity, AccountEntity>`) — *never* as a substitute for a type.

## Wishful Interface — sealed interfaces shine

A Kotlin `sealed interface` is the ideal shape for a wishful interface with a small, closed set of outcomes:

```kotlin
sealed interface Transmitter {
    fun key(frequency: Frequency, stream: AudioStream)
}

// One real adapter + one fake in tests, no plugins from outside the module
@Component
class RadioTransmitter(...) : Transmitter { ... }

class FakeTransmitter : Transmitter { ... }
```

If you want the result space to be enumerated too, sealed results pair well:

```kotlin
sealed interface KeyResult {
    object Ok : KeyResult
    data class Failed(val reason: String) : KeyResult
    data class Unreachable(val attempt: Int) : KeyResult
}

interface Transmitter {
    fun key(frequency: Frequency, stream: AudioStream): KeyResult
}
```

Caller code becomes exhaustive:

```kotlin
when (val result = transmitter.key(channel.frequency, audio)) {
    KeyResult.Ok            -> markBroadcast(channel)
    is KeyResult.Failed     -> logFailure(result.reason)
    is KeyResult.Unreachable -> scheduleRetry(channel)
}
```

## `Result<T>` and `runCatching` at the seam

Kotlin's `Result<T>` is well-shaped for translating vendor exceptions to domain outcomes **at a single layer**. Use it at the Adapter; don't let it cascade.

```kotlin
@Component
class StripePaymentGateway(private val client: StripeClient) : PaymentGateway {

    override fun charge(amount: Money, source: CardToken): Charge =
        runCatching {
            val raw = client.charges.create(
                ChargeCreateParams.builder()
                    .setAmount(amount.cents)
                    .setCurrency(amount.currency.code)
                    .setSource(source.value)
                    .build()
            )
            raw.toDomain()
        }.getOrElse { ex ->
            throw when (ex) {
                is CardException        -> CardDeclined(ex.code)
                is RateLimitException   -> GatewayBusy
                is InvalidRequestException -> GatewayContractBroken(ex.message ?: "")
                else                    -> GatewayUnreachable(ex)
            }
        }
}
```

The Adapter catches vendor exceptions exactly once, and **only** at the seam. The rest of the code catches `CardDeclined` / `GatewayBusy` — domain exceptions you defined.

> **Don't propagate `Result<T>` everywhere.** Pick one layer where it lives. If `Result<T>` shows up in the controller's signature, the service's signature, *and* the repository's signature, you've made every layer a Maybe — at which point exceptions would have been clearer.

## Extension functions as cheap adapters

When the foreign type is *almost* what you want and a class would be overkill, an extension function is the lightest adapter you can write.

```kotlin
// Inbound — vendor DTO → domain
fun Stripe.Charge.toDomain() = Charge(
    id = ChargeId(this.id),
    amount = Money(this.amount, Currency(this.currency.uppercase())),
    status = ChargeStatus.valueOf(this.status.uppercase()),
    capturedAt = Instant.ofEpochSecond(this.created)
)

// Outbound — domain → vendor request
fun Money.toStripeAmount() = this.cents
```

**Rules:**

- Extension functions stay *inside the boundary package* — they translate, and translation is a boundary concern.
- They are not used in domain code; the domain doesn't know `Stripe.Charge` exists.
- For more than ~3 fields or any non-trivial mapping, prefer a real class or a MapStruct-style mapper.

## Coroutine seams

When the vendor SDK is callback-, future-, or reactive-flavoured and your code is coroutine-flavoured (or vice versa), translate **at the Adapter**, not in business code.

```kotlin
// Callback → suspend
suspend fun TwilioClient.sendVerified(to: PhoneNumber, body: String): MessageId =
    suspendCoroutine { cont ->
        send(to.e164, body, object : Callback {
            override fun onSuccess(msg: TwilioMessage) =
                cont.resume(MessageId(msg.sid))
            override fun onFailure(e: Throwable) =
                cont.resumeWithException(SmsFailed(e))
        })
    }

// CompletableFuture → suspend
suspend fun S3Client.fetchObject(key: ObjectKey): ByteArray =
    getObjectAsync(GetObjectRequest.builder().key(key.value).build()).await().asByteArray()

// Reactor Mono → suspend  (only inside the adapter; don't let Mono escape)
suspend fun WebClient.getOrder(id: OrderId): OrderResponse =
    get().uri("/orders/{id}", id.value).retrieve().awaitBody()
```

> Once the seam translates to `suspend`, **don't accept `Mono`/`Flux`/`CompletableFuture` in business code.** They become an additional execution model the reader has to track in their head.

## Companion factory `from(...)` for inbound translation

A useful convention: every domain type that has an external counterpart owns a `Companion.from(...)` (or static factory function) for the inbound conversion.

```kotlin
data class Charge(val id: ChargeId, val amount: Money, ...) {
    companion object {
        fun from(stripeCharge: Stripe.Charge): Charge = Charge(
            id = ChargeId(stripeCharge.id),
            amount = Money(stripeCharge.amount, Currency(stripeCharge.currency)),
            ...
        )
    }
}
```

This co-locates the inbound translation with the type's invariants — same as `Order.submit()` enforces submission rules. The Adapter calls `Charge.from(...)`; the Adapter doesn't do the mapping itself.

## What about Kotlin's `kotlin.Result<T>` as a return type?

The JVM signature for `Result<T>` is awkward (see KT-29577) and many Spring features (return-type inference, controller serialisation) don't compose naturally with it. **Don't return `Result<T>` from public APIs.** It's fine *inside* a function (`runCatching { ... }.fold(...)`) and acceptable as an explicit value within a tight boundary; for cross-class/method signals prefer a sealed `Outcome<T>` of your own.

## When `data class` is the right boundary value type

A boundary often returns "what we got from the vendor" as an immutable shape. `data class` is the right tool — equality, copy, destructuring, serialisation, all free.

```kotlin
data class Charge(
    val id: ChargeId,
    val amount: Money,
    val status: ChargeStatus,
    val capturedAt: Instant
)
```

> **Caveat.** Don't make the boundary `data class` a JPA `@Entity` *and* a controller response body *and* a Kafka payload. Each layer wants its own shape; the temptation to share one type to avoid mapping is the gateway to a god type. See `clean-code-objects-and-data` for the DTO-per-layer discipline.

## Quick reference

| Kotlin feature | Boundary use |
|---|---|
| `Map<K, V>` (read-only view) | Safe to *return* from a getter — but still prefer verbs over the raw map. |
| `MutableMap` / `MutableList` | Internal-only. Never in a public signature. |
| `typealias` | Documentation, not a type. Not a boundary. |
| `@JvmInline value class` | Thin, type-safe wrapping of IDs / amounts / opaque tokens. |
| `sealed interface` | Wishful interface with a closed set of implementations. |
| `sealed Result` / `Outcome` / `Either` | Enumerated outcomes at the seam — one layer only. |
| `runCatching { ... }.getOrElse { ... }` | Translate vendor exceptions to domain exceptions at the Adapter. |
| Extension function | Cheap inbound/outbound translation; package-scoped to the adapter. |
| `companion.from(vendor)` | Inbound translation co-located with the domain type's invariants. |
| `suspendCoroutine` / `await()` / `awaitBody()` | Translate callback / future / reactive to `suspend` at the seam. |
| `data class` | Boundary value type; immutable, serialisable. One shape per layer — don't share. |
