# API at the bounded-context edge (opt-in)

Load when the API sits at the boundary of a bounded context. The contract
*is* the published language; design implications follow.

## API as published language

In DDD terms, your API is the **published language** of the bounded
context. Three audiences read it; their needs constrain the shape:

| Audience | Needs | Implication |
|---|---|---|
| Other contexts (services) | Stable, explicit, version-able | URL/proto versioning; field-level evolution discipline |
| External consumers | Discoverable, debug-friendly | One error envelope, clear status semantics |
| Reviewers | Reflects domain, not persistence | DTOs owned by the API layer, never JPA entities |

The API DTO and the aggregate root are *different shapes by design*. They
share fields by accident, not by inheritance.

## Anti-corruption at the inbound edge

When an incoming request crosses into your context, translate at the
controller:

```
[ Wire DTO ] --map--> [ Domain Command ] --invoke--> [ Aggregate ]
```

The mapping step is the anti-corruption layer. It:

- Validates *structural* things (`@Valid`, type coercion) and rejects with
  `422`.
- Translates wire names (`user_id`) to domain names (`UserId`).
- Wraps primitives in value objects (`String` → `Email`).
- Refuses to let the controller hand a wire DTO to a service.

If you ever import a generated proto class into your domain code, the
anti-corruption layer is broken.

## Aggregate root = unit of mutation

Each state-changing endpoint addresses **one aggregate root**:

- `POST /orders` — creates an `Order` aggregate. Body is a `CreateOrder`
  command, not an `Order` entity.
- `POST /orders/{id}/items` — adds an item *to* the existing `Order`. The
  aggregate boundary is the order; items mutate through it, not as their
  own resource at the same level of meaning.

URL design follows aggregate boundaries:

| URL pattern | Aggregate posture |
|---|---|
| `/orders` + `/orders/{id}` | `Order` is its own aggregate |
| `/orders/{id}/items` | `OrderItem` is *inside* `Order`'s consistency boundary |
| `/order-items/{id}` | `OrderItem` is its own aggregate (different choice; reconsider before flattening) |

When you find yourself wanting a transaction across two top-level
resources, the boundary is probably wrong.

## Command vs query at the wire

The shape of the wire DTO follows the underlying operation kind:

| Operation | Wire shape |
|---|---|
| Command (mutating intent) | `POST /resource` with command body; response is the resulting state or `202` |
| Query | `GET /resource` returning a projection; never side-effecting |
| Domain event broadcast | Async (see `messaging-boundary.md`); not a sync API at all |

CQRS splits the read and write models internally. The wire surface for each
side is still designed by this skill — separate endpoints, possibly
separate base paths (`/queries/...`, `/commands/...` when truly different).

## Don't leak ubiquitous language unintentionally

The published language is a *deliberate* subset of the ubiquitous
language. Some domain terms are intentionally hidden from external consumers:

- Internal lifecycle stages a consumer can't act on.
- Risk-scoring intermediate states.
- Reconciliation flags.

Wire DTOs carry only what the consumer can use or display. The aggregate
root keeps the rest.

## When the API feels awkward, the domain is leaking

If you can't shape a clean endpoint:
- The aggregate boundary is wrong — too big, too small, or split across
  two roots that should be one.
- The ubiquitous language has drifted from the domain (you're inventing
  new wire terms because the domain ones don't fit).
- A command is doing what should be N smaller commands.

Pair this skill with domain-design work; the contract follows the model.
