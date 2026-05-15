# No. Don't introduce `IEmailValidator`.

Your teammate is applying DIP backwards. SOLID doesn't say "wrap everything in an interface" — DIP says **invert volatile dependencies**. `EmailValidator` is neither volatile nor crossing a boundary, so the interface is pure indirection.

## DIP, properly applied

The actual rule: *source-code dependencies should point toward things that change less often than you do.* The load-bearing property is **stability**, not abstractness. An interface earns its place only if at least one of these holds:

1. **It crosses an architectural boundary** — domain↔infra, use-case↔framework, service↔external system.
2. **The concept is volatile** — implementations swap (payment providers, storage backends, notification channels).

Walk your class through both:

- **Boundary?** No. A regex check is a pure in-process function. It touches no DB, no HTTP, no framework. The registration handler and the validator live in the same layer.
- **Volatile?** No. "Is this string shaped like an email" has one answer. You're not going to swap it for `SmtpProbingEmailValidator` next quarter — and if you ever did, you'd extract the interface then, in the same commit, with the second implementation in hand. The test "*could there be another implementation someday?*" is vacuous; the real test is "*is the cost of changing this dependency today high enough to pay for the indirection?*" Here, no.

Neither condition holds. That makes `IEmailValidator` an **anemic abstraction**: pure indirection, no decoupling. Reading harder, refactoring harder, runtime identical.

## What about the other letters?

- **SRP** — one method, one actor (whoever owns registration input rules). Splitting interface from impl doesn't change actors; it just doubles the file count for the same responsibility.
- **OCP** — closed-for-modification only matters when you have multiple axes of variation. You have one regex. There's nothing to extend.
- **ISP** — a one-method interface mirroring a one-method class is the degenerate case ISP doesn't speak to. ISP segregates by client role; you have one client.
- **LSP** — moot until there's a second implementation.

## The interlock makes it clearer

DIP is the *how* behind OCP, and SRP feeds the seams where interfaces belong. None of those forces is present: no volatility to close against, no second actor, no boundary to cross. The chain is silent here — which is the signal that there's no SOLID lever to pull.

## Recommendation

Keep `EmailValidator` as a concrete class. Inject it directly into the registration handler (constructor injection, no interface). If a second validation strategy ever appears, extract `EmailValidator` to an interface *then* — it's a 30-second refactor with a real driver, instead of speculative scaffolding today.

The composition root is the only place that names concretes; one concrete with one call site is well within that budget.
