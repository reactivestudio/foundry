# Messaging boundary — when this contract shouldn't be sync at all

Load when a draft endpoint feels wrong: it kicks off long work, fans out to
many downstream services, or the caller doesn't really need the answer
*right now*.

## The deciding question

> Does the caller need the answer **inside this network round-trip** to make
> their next decision?

- **Yes** → sync (REST or gRPC). This skill applies; design the contract here.
- **No** → async (event / queue). Hand off to your messaging skill.

## Tell-tale signs you're in async territory

- The handler enqueues work and returns immediately ("fire and forget").
- More than one downstream service must succeed for the operation to be
  "done", and the caller only cares that you accepted it.
- The reasonable response is `202 Accepted` + a `Location` to a status
  resource (you've already invented an async protocol on top of sync).
- The operation can take > a few seconds in the 99th percentile.
- Failure of any downstream consumer should not roll back the caller's
  action (you want at-least-once delivery, not transactional consistency).

## Webhooks are sync-shaped async

If you're designing a webhook (an `HTTP POST` *from* you *to* a registered
consumer URL), the *transport* is sync but the *semantics* are async:

- The webhook receiver should respond `2xx` immediately and queue work
  internally.
- You should retry with backoff on non-`2xx`.
- Payloads need an idempotency key (the event ID) so receivers can dedupe.

Design the webhook contract here (URL, payload, retry policy, signature
header), but treat delivery semantics as an async problem.

## What lives on this side of the boundary

Keep designing in this skill:
- The shape of the *acknowledgement* endpoint (`POST /jobs` → `202` + job
  resource).
- The shape of the *status* endpoint (`GET /jobs/{id}`).
- The shape of the *result* endpoint (when the result is itself a resource).

## What lives on the other side

Hand off to the messaging skill for:
- Queue / topic topology.
- Event payload schema (often a different shape from the sync API DTO).
- Ordering, delivery guarantees, partitioning.
- Dead-letter handling.
- Consumer idempotency.
