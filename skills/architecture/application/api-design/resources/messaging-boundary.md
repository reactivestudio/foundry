# Delivery channel — sync vs async, pull vs push

Load when a draft interaction feels wrong: caller doesn't need the answer
right now, OR a consumer must react to changes it didn't initiate, OR the
work fans out to multiple downstream services.

## The deciding question

> Does the caller need the answer **inside this network round-trip** to
> make their next decision?

| Answer | Channel |
|---|---|
| Yes | Sync — REST or gRPC (see `rest-vs-grpc.md`) |
| No, but they need to know when it's done | Hybrid — `202` + status resource + push or event on done |
| No, fire and forget | Async event (see `events.md`, `rmq.md`, `kafka.md`) |
| Other consumers need to react too | Async event — one publish, many subscribers |

## Hybrid — the `202 Accepted` pattern

Most real systems are hybrid. The caller hits a sync endpoint, gets a fast
ack, and learns about completion through a separate channel.

```
POST /api/v1/reports
→ 202 Accepted
  Location: /api/v1/reports/r_abc
  { "id": "r_abc", "status": "QUEUED" }

# caller polls or subscribes:
GET /api/v1/reports/r_abc
→ 200 { "id": "r_abc", "status": "RUNNING", "progress": 0.42 }
→ 200 { "id": "r_abc", "status": "DONE", "resultUrl": "..." }
```

Or push completion via one of the channels below. Either way: **finish
both halves** — `202` without a way to learn the outcome is a half-built
hybrid.

## Server-to-client push — five mechanisms

When a *user-facing* consumer (browser, mobile app) needs to react to
events it didn't trigger:

| Mechanism | Best for | Limit |
|---|---|---|
| **HTTP polling** | Low frequency, simple, debuggable | Latency = poll interval; load grows with clients |
| **SSE** (Server-Sent Events) | One-way push to an open browser tab | Browser only; one-way |
| **WebSocket** | Bidi browser ↔ server | Stateful connection; scaling needs care |
| **gRPC server-streaming** | Service-to-service or mobile native | Requires gRPC client; not browser-native (gRPC-Web caveats) |
| **FCM / APNs / Web Push** | Mobile app *closed*, browser offline | OS / vendor delivery; not fine-grained real-time |

**Pick by consumer state, not aesthetic:**

| Consumer | Pick |
|---|---|
| Browser tab open | SSE (one-way) or WebSocket (two-way) |
| Mobile app foregrounded | WebSocket or gRPC stream |
| Mobile app backgrounded / killed | FCM (Android) / APNs (iOS) — no other option |
| Internal service | broker subscription (preferred) or gRPC streaming |

A common stack: **FCM/APNs wakes the app + SSE/WebSocket carries the live
session**. Push notifications announce that state changed; they aren't the
real-time channel.

## Internal service push — broker vs streaming

For service-to-service event delivery, the choice is between a broker
(Kafka / RMQ) and a gRPC server-streaming RPC:

| | Broker | gRPC server-streaming |
|---|---|---|
| Coupling | producer ↔ consumer decoupled via broker | direct connection |
| Fan-out to N consumers | natural | one consumer per stream |
| Replay / catch-up | yes (Kafka especially) | no |
| Persistence on consumer absence | yes | drops when consumer disconnects |
| Backpressure | broker buffers | stream-level flow control |
| Operational dependency | broker cluster | direct dep on the consumer |

**Default for inter-service events: a broker.** Reach for gRPC streaming
when one specific consumer needs a live feed and durability / replay
aren't the point (admin dashboard, live debugger, real-time monitoring
UI).

## Webhooks — sync transport, async semantics

A webhook is an HTTP `POST` *from you* *to a registered consumer URL*.
Transport is sync; semantics are async:

- Receiver responds `2xx` immediately and queues work internally.
- You retry on non-`2xx` with exponential backoff.
- Sign the payload (HMAC over body + timestamp) so the receiver can
  verify origin and replay-protect.
- Include an event ID in headers so the receiver can dedupe.
- Document the retry policy and the sunset rules.

Design the webhook *contract* here (URL shape, payload, signature header,
retry schedule); design the *delivery semantics* in `events.md`.

## When you've definitely got the wrong channel

- Sync `POST` returns `202` but the spec doesn't say how to learn
  completion. Half a hybrid — pick a status endpoint or a push channel.
- A WebSocket carries domain events that other services also need. The
  broker should publish; the WebSocket should subscribe to a
  consumer-group view of the topic.
- An event broker carries a request–response RPC dressed as two events
  (`order.calculation.requested`, `order.calculation.completed`). If the
  caller blocks on the response, that's sync in async clothes — use gRPC.
- "We poll every 5 seconds" when traffic grew 10× and polling now
  dominates load. Switch to push.
- Pushing real-time business events via FCM/APNs only — they're
  unreliable for ordering and timing. Use them to *announce* a change;
  pair with a real-time channel for the data.

## Hand-off

- Sync protocol details → `rest.md` / `grpc.md` / `rest-vs-grpc.md`
- Event payload + naming + schema evolution → `events.md`
- Broker-specific topology → `rmq.md` or `kafka.md`
- Auth on push channels → out of scope; pair with a security skill
