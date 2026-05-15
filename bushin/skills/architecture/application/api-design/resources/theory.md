# Theory — why the principles look the way they do

Load when you need to *justify* a contract decision (PR review, design doc),
not just apply it.

## Fielding's six constraints (REST)

REST is not "JSON over HTTP". Fielding's dissertation (2000) names six
constraints; an API earns the REST label by satisfying them:

1. **Client–server** — UI and data are separable concerns.
2. **Stateless** — every request carries the context the server needs. No
   server-side session memory between calls.
3. **Cacheable** — responses say whether they're cacheable and for how long
   (`Cache-Control`, `ETag`).
4. **Uniform interface** — resources are identified by URIs, manipulated
   through representations, messages are self-descriptive, and (the optional
   one) HATEOAS lets clients discover next actions.
5. **Layered** — proxies, gateways, CDNs can sit between client and origin
   without the client knowing.
6. **Code-on-demand** *(optional, rarely used)* — server can send executable
   code to extend the client.

Practical takeaways the body principles encode:
- **Stateless** ⇒ idempotency must come from request data (the
  `Idempotency-Key` header), not from server session state.
- **Cacheable** ⇒ `GET` must be safe; cache layers depend on this.
- **Uniform interface** ⇒ one error envelope, consistent status semantics,
  resources as nouns.

## Richardson Maturity Model

Useful frame for grading existing APIs:

| Level | Marker | What you have |
|---|---|---|
| 0 | One URL, `POST` everything | SOAP-shaped JSON. Not REST. |
| 1 | Multiple resource URLs | Resources, but every operation is `POST`. |
| 2 | HTTP methods used correctly | Real REST baseline — what the body Principles target. |
| 3 | HATEOAS | Hypermedia-driven. Adopt only when a client genuinely walks links. |

Level 2 is the realistic target. Skipping to 3 without a client that needs
it is over-engineering.

## "Contract-first" — why before the code

Three audiences read your contract; each pays a different cost when it
changes:

| Audience | Read via | Cost of a breaking change |
|---|---|---|
| Machines (parsers, generated clients) | OpenAPI / `.proto` | Compile errors across every consumer language |
| Developers (humans on partner teams) | curl, docs, Swagger UI | Re-learn endpoints, update internal docs |
| Reviewers (PR readers, auditors) | The spec | Re-audit the entire surface |

A handler change costs you a deploy. A contract change costs *every consumer*
a coordinated migration — sometimes across orgs you don't control. Locking
the contract first is the cheapest sequencing.

## What this means for daily decisions

- The status code is not "a number you pick" — it's the part of your
  response that proxies, monitors, retries, and generic HTTP clients read.
  Lie about it and they all break silently.
- The error envelope is not "a JSON shape" — it's a contract that every
  consumer's error-handling code is coupled to. Per-endpoint shapes
  multiply that coupling.
- Versioning is not "what we'll do later" — every endpoint without a version
  is implicitly `v∞`, which means *any* change is breaking.
