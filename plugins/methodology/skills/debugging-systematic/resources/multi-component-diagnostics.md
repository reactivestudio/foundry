# Multi-Component Diagnostics

> When a system fails across multiple layers (CI → build → signing, controller → service → DB → cache, producer → broker → consumer), Phase 1 of `SKILL.md` cannot identify the right layer without evidence at each boundary.

The pattern: **before proposing fixes, add diagnostic instrumentation at every component boundary, run once, and let the output tell you where the break is.** This converts a guess-and-check session ("maybe it's the DB? maybe it's auth?") into a single-pass localization.

## When to use this pattern

- The error surfaces at the top layer but the broken value is set somewhere underneath.
- You suspect a configuration / secret / env var isn't propagating but don't know which hop loses it.
- Multiple components are touched by the request, and you don't know which one is misbehaving.
- A test passes in isolation but fails when run end-to-end.

## The instrumentation pass

For each boundary, log three things:
1. **What enters the component** (inputs, params, headers, env, config).
2. **What exits the component** (response, return value, side effect, persisted state).
3. **What changed in the environment** (DB row before/after, queue length, cache key, file timestamps).

Run the failing scenario *once*. Read all three at every boundary. The first boundary where input is correct but output is wrong **is the failing component**.

## Example — CI / build / signing failure (shell)

A common shape: GitHub Actions secret should propagate to a build script, which should hand it to a signing command. The signing command says "missing identity." Where did the secret get lost?

```bash
# Layer 1: workflow (top of the chain)
echo "=== Secrets available in workflow ==="
echo "IDENTITY: ${IDENTITY:+SET}${IDENTITY:-UNSET}"

# Layer 2: build script
echo "=== Env vars in build script ==="
env | grep IDENTITY || echo "IDENTITY not in environment"

# Layer 3: keychain state (signing prerequisites)
echo "=== Keychain state ==="
security list-keychains
security find-identity -v

# Layer 4: actual signing command
codesign --sign "$IDENTITY" --verbose=4 "$APP"
```

Reading this output left to right tells you exactly which hop loses the secret. **You don't need to guess** — you read which layer was the last one where it was present.

## Example — Kotlin/Spring request path

The same pattern applies inside one Spring service that spans controller → service → repository → external client. Use structured logging or a temporary debug aspect:

```kotlin
// At the controller boundary
log.info("CTRL in: userId={}, correlationId={}", userId, correlationId)
val result = orderService.placeOrder(userId, cmd)
log.info("CTRL out: result={}", result)

// At the service boundary
log.info("SVC in: userId={}, cmd={}", userId, cmd)
val order = repository.save(order)
log.info("SVC saved: orderId={}", order.id)
val payment = paymentClient.charge(order)
log.info("SVC paid: paymentId={}, status={}", payment.id, payment.status)

// At the repository boundary — Spring Data slow query log is often enough
// spring.jpa.show-sql=true + a custom interceptor

// At the external client boundary
log.info("HTTP out: POST {} body={}", url, body)
val response = restClient.post(...).body(...)
log.info("HTTP in: status={} body={}", response.statusCode, response.body)
```

Run the failing request once. The first log line where the value is right going in but wrong (or missing) going out is your culprit.

## Example — async / messaging path

For producer → broker → consumer:

```kotlin
// Producer side
log.info("PUB out: topic={} key={} payload={}", topic, key, payload)
rabbitTemplate.convertAndSend(exchange, routingKey, payload)

// On the broker — use management UI or `rabbitmqctl`:
//   rabbitmqctl list_queues name messages messages_ready
//   rabbitmqctl list_bindings | grep <routing-key>

// Consumer side — the @RabbitListener entry
@RabbitListener(...)
fun onEvent(payload: EventDto, @Header(...) headers: MessageHeaders) {
    log.info("SUB in: headers={} payload={}", headers, payload)
    // ... processing
    log.info("SUB done: result={}", result)
}
```

Loss between PUB and the broker means binding / routing-key mismatch. Loss between the broker and SUB means consumer ack/nack/DLQ issues. Loss after SUB-in means it's a processing bug, not a transport bug.

## What to do with the output

1. Identify the first boundary where input is correct but output is wrong / absent.
2. **That component** is the failing one. Continue Phase 1 *inside* it, not across the whole system.
3. Remove the instrumentation once the root cause is fixed (or, for repeating issues, promote it from `log.info` to structured tracing / metrics).

## Anti-patterns of multi-component instrumentation

- **Instrumenting only the suspected layer.** That presupposes the answer. Instrument every boundary in the failing path; let the evidence pick.
- **Adding instrumentation and acting on it before running once.** Run, read, *then* decide.
- **Leaving the instrumentation in forever as `log.info`.** It pollutes production logs. Either remove or promote to metrics/traces with proper sampling.
- **Logging secrets / PII** in the instrumentation. Use `${X:+SET}${X:-UNSET}` style — log presence, not value.

## The deeper point

This pattern is mechanical for a reason: it removes the temptation to guess. When you can read the failure point off a log, hypothesis-forming becomes evidence-based. You're no longer asking "could it be X?" — you're asking "we see Y; what produced Y?"
