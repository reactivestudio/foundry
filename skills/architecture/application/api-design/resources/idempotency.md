# Idempotency

Load when designing any state-changing `POST` whose retry could cause real
harm: payments, message sends, ticket creation, inventory decrement,
fan-out to external systems.

## The pattern (Stripe-canonical)

```
POST /payments
Idempotency-Key: 7f4e9a02-1c8b-4f4a-9c6a-1c0a2b3c4d5e
Content-Type: application/json

{ "amount": 5000, "currency": "USD", "source": "card_..." }
```

Server stores `(key, request_hash, response)` for a TTL. On a duplicate
request:

| Scenario | Server action |
|---|---|
| Same key, same body, original still processing | Either `409 Conflict` ("retry later") or block until done |
| Same key, same body, original finished | Replay the stored response (same status, same body) |
| Same key, **different** body | `422 Unprocessable Entity` — key was reused with a different intent |
| New key | Process normally; store the response |

## Why a header, not a request field

- Generic middleware (rate-limiter, audit log, retry library) can read the
  header without parsing the body.
- Same idempotency policy works for `POST`s with binary or no body.
- Stripe's convention — battle-tested.

## What to hash

Hash should cover everything that *defines the intent*:
- Request body (canonicalised JSON — sort keys, drop whitespace).
- Path and query string.
- Optionally: authenticated principal (so two users with the same key
  don't collide).

Headers like `Authorization`, `User-Agent`, `Date` — *don't* include.
They change between retries even when intent is identical.

## Storage and TTL

Plain Kotlin sketch (storage-agnostic):

```kotlin
data class IdempotentRecord(
    val key: String,
    val requestHash: String,
    val response: SerializedResponse,
    val storedAt: Instant,
)

interface IdempotencyStore {
    fun get(key: String): IdempotentRecord?
    fun putIfAbsent(record: IdempotentRecord): Boolean   // returns false if key already present
    fun deleteExpired(olderThan: Instant)
}
```

TTL guidance:

| Operation class | Typical window |
|---|---|
| User-facing payment / order | 24 hours |
| Internal job submission | 1 hour |
| High-volume retries with short backoff | 5–15 minutes |

Long TTLs cost storage; short TTLs let aggressive retries hit the database
twice. Tune to the consumer's actual retry policy.

## Who generates the key

The **client** does. Each logical operation gets a fresh UUID. Retries of
*the same operation* reuse the key. The client library should generate it
once per "attempt" and reuse across the retry-loop:

```kotlin
fun createPayment(req: CreatePaymentRequest): Payment {
    val key = UUID.randomUUID().toString()
    return retry(maxAttempts = 5, backoff = exponential(100.ms)) {
        http.post("/payments") {
            header("Idempotency-Key", key)   // same on every attempt
            body(req)
        }
    }
}
```

If the *server* generates the key on a duplicate-without-key, you've
defeated the purpose — the client's retry was meant to be safe.

## What is and isn't natively idempotent

Native (no key needed):

- `GET`, `HEAD`, `OPTIONS` — safe, idempotent by spec.
- `PUT` — idempotent by spec (replace is replace).
- `DELETE` — idempotent by spec (second delete returns `404`, which is the
  correct "already gone" answer).

Needs a key:

- `POST` that creates something — without a key, two calls = two resources.
- `POST` that triggers an external side effect (email send, payment
  capture, webhook fan-out).
- `PATCH` that is logically a delta (`balance += 100`) — running it twice
  doubles the effect.

## gRPC

No standard header equivalent. Two options:

1. **Carry the key in the request message** — add an `idempotency_key`
   field to the request. Document it.
2. **Use a `Metadata` (gRPC header)** — `idempotency-key` in
   call metadata. More aligned with HTTP semantics but less type-safe.

Pick one per service and apply it consistently.

## Common mistakes

- Storing only `(key, response)` without `request_hash` — same key with a
  different body returns the cached response, silently doing the wrong
  thing.
- Storing only `(key, request_hash)` without the response — every duplicate
  re-runs the operation.
- Letting the *server* mint a key when the client didn't send one — defeats
  the safety net.
- TTL shorter than the client's retry budget — duplicate after window
  expires re-runs the operation.
- Hashing including `Date` / `Authorization` — every retry hashes
  differently and looks "new".
