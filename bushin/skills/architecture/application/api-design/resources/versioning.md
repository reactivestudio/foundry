# Versioning

Load when introducing `v2`, weighing strategies, or arguing for `v1` on a
brand-new endpoint.

## The five strategies

| Strategy | Example | When it wins |
|---|---|---|
| **URL prefix** | `/api/v1/users` | Default for REST. Visible in logs, in curl, in browser. Trivial to route at the gateway. |
| **Media type** | `Accept: application/vnd.example.user.v2+json` | Strict REST purists. Keeps URLs clean. Hard to test casually. |
| **Header** | `X-API-Version: 2` | Mostly the same trade-offs as media type. |
| **Query parameter** | `/api/users?version=2` | Quick A/B in tests. Easy to forget and silently fall back to default. |
| **Package (gRPC)** | `package com.example.user.v1;` | Idiomatic for protobuf. Field numbers + package version catch drift at build time. |

**Default for new REST APIs:** URL prefix. The cost of "ugly URLs" is
trivial compared to the cost of versioning being invisible in logs.

**Default for new gRPC APIs:** package version.

## When to bump (what counts as breaking)

Breaking changes — bump the version:

- Removing a field or method.
- Renaming a field (semantically equivalent to remove + add).
- Changing a field's type or meaning.
- Tightening validation (a previously-accepted value now rejected).
- Changing default behaviour (e.g. a default page size dropped from 50 to
  20 will hurt clients that relied on the old default).
- Changing error semantics in a way that consumers' error-handling could
  trip on (e.g. moving from `409` to `422` for the same situation).

Non-breaking — stay on the current version:

- Adding a new optional field with a sensible default.
- Adding a new endpoint.
- Adding a new optional query parameter.
- Adding a new error type (consumers' default branch should catch it).
- Loosening validation (previously-rejected values now accepted).

## Running v1 and v2 together

Real migrations are weeks-to-months, not minutes. Plan for both versions in
production:

1. Ship v2 alongside v1. Both routes live. Both deployments build.
2. Announce a sunset date for v1. Include `Sunset:` header on v1 responses
   (RFC 8594):
   ```
   Sunset: Sat, 31 Dec 2026 23:59:59 GMT
   Deprecation: true
   Link: <https://docs.example.com/migrate-v2>; rel="deprecation"
   ```
3. Monitor v1 traffic. Don't kill until it drops to a known-acceptable
   level.
4. Retire v1. Keep the URL returning `410 Gone` with a `ProblemDetail`
   pointing at the migration guide, for at least one more release cycle.

## gRPC specifics

- New package, new file, new generated service: `com.example.user.v2`.
- Mark v1 methods `option deprecated = true;` with a comment naming the
  v2 replacement.
- Field-level evolution *within* v1: only new optional fields, never
  repurpose existing field numbers.

## Don't

- Version inside the request body. Invisible in URLs, undebuggable from
  logs, easy to forget.
- "v1.1", "v1.2" minor versions on the wire. The wire knows breaking vs
  non-breaking; semver-style minors don't add information.
- Single-deploy "atomic switchovers" — every real consumer needs migration
  time.
- "We'll add versioning when we need v2." You need it on day one; adding
  later costs an order of magnitude more.

## Cost of skipping v1 from launch

Without `v1` in the URL:
- Every endpoint becomes implicitly v∞.
- *Any* breaking change requires inventing the versioning scheme retroactively
  and migrating consumers off the unversioned URLs.
- Logs, dashboards, and rate-limit buckets have no version dimension to
  slice by.

The day-one cost of `v1` in the URL is ~zero. The day-N cost of adding it
later is the migration of every consumer you have.
