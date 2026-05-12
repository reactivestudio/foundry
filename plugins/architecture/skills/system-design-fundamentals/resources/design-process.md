# The 7-Phase Design Process

The structured way to take a system from "we need this" to "let's build it."

---

## Phase 1 — Clarify

**Goal:** make the problem precise.

Before any architecture talk, answer:

### Functional requirements

- **What does the system do?** State in 1-3 sentences. ("Shorten URLs and resolve them back. Anonymous users; some auth users get analytics.")
- **Who are the users?** Volume per type. ("100M anonymous visitors / month; 100K registered creators.")
- **What's in scope vs out?** Explicit non-goals. ("In scope: short-URL service. Out of scope: custom domains.")

### Non-functional requirements

This is where designs differ. **Always force concrete numbers:**

| NFR | Question |
|---|---|
| **Latency** | p50 / p99 / p99.9 — for which operations? |
| **Throughput** | reads/s and writes/s, peak and average |
| **Durability** | "OK to lose last 5 min of data" vs "must persist before ACK" |
| **Consistency** | strong / read-your-writes / eventual / which-per-operation |
| **Availability** | 99.9% / 99.99% — agreed downtime budget |
| **Geography** | single region / multi-region / global edge |
| **Cost ceiling** | per-month budget — drives a lot of decisions |
| **Security / compliance** | PII, payments, regulation (HIPAA, PCI, GDPR) |
| **Time-to-launch** | weeks vs years |

### Output of Phase 1

A 1-paragraph problem statement + a table of NFRs with **numbers, not adjectives** ("fast" → "p99 ≤ 200ms").

---

## Phase 2 — Estimate

**Goal:** make capacity numbers concrete.

### What to estimate

- **QPS (queries per second)** — read and write separately. Average + peak.
- **Storage** — total + growth rate.
- **Bandwidth** — in / out, per region.
- **Memory** — caches, working set.
- **Number of instances** — back-of-envelope per component.

See `capacity-estimation.md` for the methodology and numbers to memorise.

### Worked example — URL shortener

**Given:** 100M new short-URLs / month, 1B redirects / month, average URL 100 bytes long, retain forever.

```
Writes:     100M / month / 30 / 86400 = ~40 writes/s        (peak ~5×= 200/s)
Reads:      1B / month / 30 / 86400 = ~400 reads/s          (peak ~5×= 2000/s)
Read/write: ~10:1                                          → read-heavy, cache helps
Storage:    100M × 100B × 12 months × 5 years = 600 GB     → fits in one DB instance
Bandwidth:  redirect = 1 KB resp × 400/s = 0.4 MB/s         → trivial
```

These numbers immediately tell you:
- **One Postgres instance is enough** for storage
- **Cache is the right optimisation** (read-heavy)
- **No sharding needed yet**
- **No multi-region needed for cost**

Numbers prevent over-engineering.

### Output of Phase 2

A table of estimates. Even if approximate, **on paper**. The number "200 writes/s peak" rules out 100 different architectures.

---

## Phase 3 — High-level design

**Goal:** boxes and arrows — the major components and how they connect.

### What goes in the diagram

- **Clients** (web, mobile, API consumers)
- **Edge** (load balancer, CDN, API gateway)
- **Services** (the boxes — usually 3-7 at high level)
- **Data stores** (the cylinders — primary, cache, search index, etc.)
- **Async fabric** (message broker, event bus)
- **External integrations** (payment, email, auth, etc.)

### Worked example — URL shortener

```
                ┌─────────────┐
                │   Browser   │
                └──────┬──────┘
                       │ HTTPS
                ┌──────▼──────┐
                │     CDN     │  ← static + cached redirects for hot URLs
                └──────┬──────┘
                       │
                ┌──────▼──────┐
                │ Load Balancer│
                └──────┬──────┘
                       │
            ┌──────────┼──────────┐
            │          │          │
        ┌───▼──┐   ┌──▼───┐   ┌──▼───┐
        │ App  │   │ App  │   │ App  │  ← stateless service
        └───┬──┘   └──┬───┘   └──┬───┘
            │         │           │
            └─────────┼───────────┘
                      ▼
            ┌─────────────────────┐
            │   Redis (cache)     │  ← short → long resolution
            └─────────┬───────────┘
                      │ miss
            ┌─────────▼───────────┐
            │   PostgreSQL        │  ← source of truth
            └─────────────────────┘
                      │ events
            ┌─────────▼───────────┐
            │   Kafka             │  ← analytics events
            └─────────┬───────────┘
                      │
            ┌─────────▼───────────┐
            │   Clickhouse        │  ← analytics projection
            └─────────────────────┘
```

This diagram says everything important: stateless app, cache-aside Redis, source-of-truth Postgres, analytics via async Clickhouse projection. No premature complexity.

### Output of Phase 3

A clean diagram with **5-10 boxes max**. If you have 20, you're already in Phase 4.

---

## Phase 4 — Component design

**Goal:** what does each box do?

For each component:
- **Responsibility** — one paragraph
- **API** — what calls in, what comes out
- **Dependencies** — which other boxes
- **Failure mode** — what happens when this is down

### Worked example — URL shortener "App service"

> Responsibility: receive POST /shorten and GET /:code. On shorten: generate a code, store mapping, return short URL. On resolve: look up code, redirect to original.
>
> APIs:
> - POST /shorten { url } → 201 { code, shortUrl }
> - GET /:code → 302 Location: <originalUrl>
> - GET /:code/analytics (auth required) → { clicks, geo, devices }
>
> Dependencies: Postgres (writes, durable lookup), Redis (cache, hot lookup), Kafka (publish redirect events).
>
> Failure mode: Postgres down → 503; Redis down → degrade to direct Postgres reads (slower, still works); Kafka down → fire-and-forget, no user-facing impact, just lost analytics.

This level of detail clarifies whether your design hangs together.

### Output of Phase 4

A one-page description per major component. Reveals overlaps, missing pieces, hidden coupling.

---

## Phase 5 — Detail design

**Goal:** the meaty technical decisions.

### What to drill into

| Detail | Example for URL shortener |
|---|---|
| **Data model** | `urls(code PK, original_url, created_at, created_by, clicks_count)` |
| **ID generation** | Base62 of 64-bit counter, or random 7-char (collision-checked) |
| **Cache key/value/TTL** | key = `code`, value = `original_url`, TTL = 1 hour |
| **API contracts** | OpenAPI / proto definitions |
| **Critical algorithms** | Pseudo-code for code generation, redirect logic |
| **Transactional boundaries** | Where do you commit? What's idempotent? |
| **Event schemas** | `UrlCreated { code, url, createdAt }`, `UrlVisited { code, ip, ua, at }` |

### Specific detail: code generation strategies

| Strategy | Pros | Cons |
|---|---|---|
| Auto-increment + Base62 encode | Simple, no collisions | Predictable codes (security leak), DB single-writer |
| UUID-based | Distributed | Long codes (22+ chars Base62) |
| Random 7-char + collision check | Short codes | Extra DB read per write to check collision |
| Snowflake / ULID + Base62 | Sortable, distributed | More moving parts |

You pick based on Phase 2 estimates: 100M codes ⇒ Base62 7-char (62⁷ = 3.5T) gives 30K-year code space with retry-on-collision.

### Output of Phase 5

Diagrams + tables of data models, API specs, algorithms. Enough that an engineer could start typing.

---

## Phase 6 — Bottlenecks

**Goal:** where will this break first?

For each component, ask:
- **CPU bound?** ("compress every analytic event" is CPU-bound)
- **Memory bound?** ("hold entire URL → owner map in memory")
- **I/O bound?** ("every redirect = Postgres point read")
- **Network bound?** ("100MB JSON payloads")
- **Lock bound?** ("global counter shared across instances")

### Worked example — URL shortener

| Component | Bottleneck risk |
|---|---|
| App service | None at 2K req/s; stateless scales horizontally |
| Redis | Memory: 100M × ~100B = 10GB. Fits one Redis node. Cluster needed at 10× growth. |
| Postgres writes | 200 writes/s peak — trivial for single instance |
| Postgres reads | 2K reads/s with cache hit rate 90% = 200 cold reads/s — trivial |
| Kafka | 400 events/s — single partition handles 10× this |
| Clickhouse | Inserts are cheap; OLAP queries are the constraint, query-pattern-dependent |
| ID generation | Single counter = bottleneck → use Snowflake / random + collision check |

### Failure to identify a bottleneck

Common ones I've seen missed in interviews:
- **N+1 inside a "single API call"** — page-load fan-out you didn't notice
- **Cache stampede** — if 100K clients hit a cold key simultaneously, the DB takes them all
- **Connection pool exhaustion** — well before CPU/memory
- **External-service timeout chain** — sync call A → B → C → D, each 1s timeout, total 4s
- **Hot partition** — 99% of traffic to 1% of keys breaks sharded systems

### Output of Phase 6

A list of "will break at X" thresholds, with mitigations identified.

---

## Phase 7 — Scale

**Goal:** how do we 10× / 100× the load?

For each bottleneck from Phase 6, name the scaling tactic:

| Component | At 10× current | At 100× current |
|---|---|---|
| App | Add instances | Multi-region |
| Redis | Bigger node or cluster | Cluster + read replicas per region |
| Postgres reads | Read replicas | Sharding by code prefix |
| Postgres writes | Vertical scaling | Sharding |
| Kafka | More partitions | Multi-cluster |
| Clickhouse | More replicas | Per-region clusters + global aggregate |

### Don't pre-scale

The biggest mistake: design for 100× when you have 1×. Pay the engineering cost only when needed.

**Identify the migration path**, not the scaled architecture.

### Output of Phase 7

A short table of "if traffic 10×, do X" entries. Names the path, doesn't commit to building it.

---

## Communicating the design

A good system design **answers questions in order**:

1. *What are we building?* (Phase 1 — 1 paragraph)
2. *How much load?* (Phase 2 — 1 table)
3. *What does it look like?* (Phase 3 — 1 diagram)
4. *What does each piece do?* (Phase 4 — paragraph per component)
5. *Show me the data model / APIs / key algorithms.* (Phase 5 — tables + code)
6. *Where will this break first?* (Phase 6 — list)
7. *How do we scale?* (Phase 7 — table)

Documents in the wild (RFC, design doc, ADR) usually follow this order. Interview answers should too.

---

## When to iterate

After Phase 6, expect to revisit:
- Phase 3 if a fundamental component must change ("we need a search index, not just Postgres")
- Phase 2 if your bottleneck reveals an estimation mistake
- Phase 1 if a requirement turns out to be wrong or missing

Iteration is the job, not failure. Resist the urge to defend the design you started with.

---

## System design interview specifics

If preparing for FAANG-style interviews, the rubric is:

1. **Clarification** — ask for NFRs, scope, scale. Don't assume.
2. **Estimation** — show numbers, even rough. They want to see you've internalised hardware costs.
3. **High-level** — diagram quickly; don't over-detail.
4. **Deep dive** — interviewer picks a component, you go deep. This is where seniority shows.
5. **Trade-offs** — be honest about what you're giving up. "I chose cache-aside; the cost is stale reads up to TTL."
6. **Bottlenecks + scale** — show that you've thought past the happy path.

Common interview failures:
- Jumping to a design without asking
- Buzzword soup with no numbers
- Missing the obvious bottleneck
- Pretending you've never seen the problem before (most are well-known patterns — show that)
- Defending a flawed design instead of refining
