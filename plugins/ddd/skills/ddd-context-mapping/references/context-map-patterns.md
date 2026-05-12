# Context Mapping Patterns

## Common relationship patterns

| Pattern | When | Power dynamic |
|---|---|---|
| **Partnership** | Two contexts succeed or fail together; teams coordinate on changes | Equal |
| **Shared Kernel** | A small shared model owned jointly | Equal but constrained |
| **Customer-Supplier** | Upstream commits to downstream's needs; downstream depends on upstream | Downstream has influence |
| **Conformist** | Downstream accepts upstream's model as-is, no translation | Upstream wins |
| **Anti-Corruption Layer (ACL)** | Downstream translates upstream's model into its own ubiquitous language | Downstream protects itself |
| **Open Host Service (OHS)** | Upstream publishes a public protocol that many downstreams use | Upstream defines |
| **Published Language** | A formal shared schema (the wire format), often paired with OHS | Both sides honour the contract |
| **Separate Ways** | No integration; teams agree to not connect | None |

### Quick chooser

```
Need to integrate two contexts?
│
├── Same team owns both
│   └── Partnership (or Shared Kernel for small shared model)
│
├── Different teams; upstream is willing to serve downstream needs
│   └── Customer-Supplier
│
├── Different teams; upstream is fixed (vendor, legacy, external API)
│   ├── Downstream is OK with vendor's terms
│   │   └── Conformist
│   └── Downstream wants to keep its language clean
│       └── Anti-Corruption Layer  ← almost always the right answer for vendors
│
├── Upstream serves many downstreams; needs a stable public contract
│   └── Open Host Service + Published Language
│
└── Both contexts agreed not to integrate
    └── Separate Ways
```

## Mapping template

| Upstream context | Downstream context | Pattern | Contract owner | Translation needed | Notes |
| --- | --- | --- | --- | --- | --- |
| Billing | Checkout | Customer-Supplier | Billing | Yes | Checkout depends on Billing's `Invoice` shape |
| Identity | Checkout | Conformist | Identity | No | Checkout accepts the user model as-is |
| GitHub API | Code | Anti-Corruption Layer | Code (the consumer) | Yes | Vendor model → domain language |
| Code | Search | Open Host Service + Published Language | Code | Yes | Stable event published in `contract/` |

Fill this for every pair of contexts that exchange data.

## Anti-Corruption Layer — when and how

The ACL is **the** pattern for external vendor integration. Whenever you depend on a vendor model (GitHub, Jira, Slack, Stripe, internal legacy), the ACL keeps the vendor's vocabulary out of your domain.

### Structure

```
┌─────────────────────────────────────────────────────────────────────┐
│ Bounded Context (e.g. Code)                                         │
│                                                                     │
│ ┌──────────────────────────┐    ┌──────────────────────────────┐   │
│ │ Domain Core               │    │ Anti-Corruption Layer (ACL)  │   │
│ │ • Entities (PullRequest) │ ◀──│ • Adapter: GitHubPullRequest │   │
│ │ • Value objects          │    │   → PullRequest mapping       │   │
│ │ • Repositories           │    │ • Adapter: stable port        │   │
│ │ • Domain events          │    │ • Failure / retry / fallback  │   │
│ └──────────────────────────┘    └──────────────────────┬───────┘   │
│                                                         │           │
└─────────────────────────────────────────────────────────┼───────────┘
                                                          │
                                                          ▼
                                                   ┌─────────────┐
                                                   │ Vendor API  │
                                                   │ (GitHub)    │
                                                   └─────────────┘
```

### ACL checklist

- **Define canonical domain model first.** What does `PullRequest` mean in your domain, independent of any vendor?
- **Translate at the boundary.** Vendor terms (`commit_sha`, `head_ref`) → domain terms (`changeSet`, `targetBranch`).
- **Keep ACL code at the boundary, not inside domain core.** The domain core should not import vendor SDKs.
- **One ACL per vendor.** Each external system has its own translation layer; do not unify them.
- **Failure modes are part of the ACL.** What if the vendor returns malformed data, is down, rate-limits us? Decide here, not in the domain.
- **Contract tests for mapped behavior.** Replay recorded vendor responses; verify the domain sees what it expects.
- **Versioning policy.** When the vendor breaks the contract, the ACL absorbs it; the domain doesn't notice.

### Where the ACL lives in code (Kotlin/Spring)

```
module/code/
├── domain/                    # No vendor imports here
│   ├── PullRequest.kt
│   ├── ChangeSet.kt
│   └── PullRequestRepository.kt   (interface)
└── infrastructure/
    └── github/                # The ACL
        ├── GitHubClient.kt          (raw vendor SDK calls)
        ├── GitHubPullRequestMapper.kt   (vendor JSON → domain)
        ├── GitHubPullRequestAdapter.kt  (implements PullRequestRepository)
        └── GitHubRetryPolicy.kt
```

The domain layer imports nothing from `org.kohsuke.github` or any other vendor SDK. The adapter sits at the boundary.

## Contract ownership matrix

For each pair, write down who owns each part of the contract:

| Concern | Owned by upstream | Owned by downstream | Co-owned |
|---|---|---|---|
| Schema definition (the wire format) | Open Host Service | Anti-Corruption Layer | Partnership |
| Versioning policy | OHS | ACL (consumer-driven) | Customer-Supplier |
| Breaking change discipline | OHS publisher | — | Partnership |
| Failure semantics (retry, fallback) | — | Always the downstream | — |
| Performance contract (SLA) | OHS publisher | — | Partnership |

The **most common mistake** is letting "ownership" be implicit. Make it explicit per pair.

## Published Language patterns

For Open Host Service, the published language usually lives in:

- A shared **`contract/`** Maven module or Gradle module (events, IDs, value objects only — no behaviour).
- An **OpenAPI / gRPC `.proto`** file in a shared schema repo.
- A **versioned message envelope** on a message bus (e.g. CloudEvents).

Rules for published language:
- **Smallest stable surface.** Don't expose your internal aggregate; expose a focused event or DTO.
- **Past-tense events** (`PullRequestMerged`, `OrderShipped`) — they describe facts, not commands.
- **Versioned at the package / namespace level.** `com.example.code.v1.PullRequestMerged` → `v2` is a new type, not a mutation.
- **Never expose JPA entities** as the published language. The entity is internal; the event is public.

## Risks per pattern

| Pattern | Common failure mode | Mitigation |
|---|---|---|
| Conformist | Vendor changes break you silently | Add an ACL even if you "didn't think you needed one"; document the conformist decision in an ADR |
| ACL | Becomes a god-class that does too much | One mapper per vendor concept; not one mapper per vendor |
| Shared Kernel | Kernel grows unboundedly; coordination cost explodes | Cap the kernel's size; review every change |
| OHS + Published Language | Backward-incompatible change ships, downstreams break | Versioning policy + deprecation window |
| Partnership | Teams' priorities diverge; "partnership" becomes blocker | Promote one to upstream/downstream relationship |
| Customer-Supplier | Upstream over-commits to downstreams' wishes | Capacity-based prioritisation; written agreement |

## Common mistakes

- **Implicit context mapping.** "We just call their API" — no, you're conformist, and you've accepted their model into your domain.
- **One generic ACL "for all vendors".** Each vendor gets its own ACL; sharing is premature abstraction.
- **Treating internal contexts like external vendors.** Internal pairs can be Customer-Supplier or Partnership; using ACL for every internal pair is over-engineering.
- **No versioning in the published language.** "We'll just change it" — and every downstream breaks at once.
- **Forgetting failure semantics.** "It works in the happy path" — what about timeouts, rate limits, malformed data?
