# Should you split `UserService` into four classes?

**No. Keep it as one class.** This is speculative SRP-theater, not SRP.

## The actual rule

Uncle Bob's SRP is **not** "one method per class" or even "one verb per class." The canonical formulation is:

> A module should have **one, and only one, reason to change**.
> A class should be responsible to **one actor** (one group of stakeholders).

The "reason to change" is a **human/business axis**, not a syntactic one. Two methods belong together if the same stakeholder, for the same reason, would request changes to both.

## Apply it to your case

- All four methods are **maintained by the same auth team**.
- All four operate on the same conceptual entity (`User` lifecycle).
- A change to the password policy, session model, or user schema will almost certainly touch several of them at once.
- There is **one actor** here: the auth/identity team.

By the actual SRP definition, `UserService` already has one responsibility: **manage the user account lifecycle**. Register / login / update / delete are the natural CRUD-shaped operations of that one responsibility, not four independent responsibilities that happen to share a file.

## What the split actually buys you

Almost nothing, and it costs you:

1. **Four files, four constructors, four sets of dependencies** that are 80% overlapping (same `UserRepository`, same `PasswordHasher`, same `EventPublisher`, same `AuditLogger`).
2. **Shared invariants get harder to enforce.** "You can't delete an account with active sessions" now spans `AccountDeleter` and `LoginService` — the invariant lives in the gap between classes instead of inside one.
3. **Transaction boundaries fragment.** `register()` often needs to atomically create a user + issue initial session; splitting forces orchestration across services.
4. **Naming gets worse.** `ProfileUpdater` and `AccountDeleter` are anemic verbs-as-nouns — a classic smell that you've turned methods into classes.
5. **No testability gain.** A 4-method class is already trivially testable; splitting doesn't reduce coupling, it just spreads it.

This is the pattern Martin himself warns about: **needless decomposition driven by a misreading of SRP**. It produces the "shotgun surgery" anti-pattern in reverse — one logical change now requires editing four files.

## When the split WOULD be right

Split when you see real signals, not syntactic ones:

- **Different actors.** E.g. `login()` is owned by the security team (MFA, rate limiting, session policy) while `updateProfile()` is owned by a product/profile team. Different change cadence, different reviewers — that's two responsibilities.
- **Different rates of change.** Login logic churns weekly (new auth providers, MFA changes); profile update is stable for years. The fast-changing part is dragging tests/reviews on the stable part.
- **The class crossed a real size threshold** (say, 500+ lines, 15+ methods, 8+ collaborators) and natural seams have emerged — typically along read-vs-write, sync-vs-async, or actor lines.
- **You need different lifetimes/scopes** (e.g. login is request-scoped with a session bean; account deletion is a background job).

None of those apply to your 4-method, single-team service.

## Concrete recommendation

1. **Reject the split.** Push back on the new engineer — politely, with the "one actor / one reason to change" framing. This is a great teaching moment: SRP is about **change axes**, not method counts.
2. **Revisit if and when** (a) ownership splits across teams, (b) the class grows past ~300–500 LOC with clearly diverging concerns, or (c) you find yourself writing comments like "// auth stuff below, profile stuff above" — those are real seams.
3. **If something must move out today**, the realistic candidates are *cross-cutting* helpers, not vertical slices: extract `PasswordHasher`, `SessionIssuer`, `UserValidator` as collaborators. That improves cohesion of `UserService` without exploding it into four anemic shells.

**Bottom line:** "Four methods, one team, one entity" = one class. Splitting it to "follow SRP" follows the letter of a misremembered rule and violates its spirit. Don't do it.
