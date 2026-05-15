# Structuring `UserService` for ISP

## Recommendation: role interfaces, defined by the consumer

Split `UserService` into **small role interfaces**, one per consumer's actual need. Keep the concrete `UserService` class as a single implementation that happens to implement all of them. Do **not** create one fat `IUserService` interface listing all 12 methods.

This is the classic "Interface Segregation Principle" answer, and it lines up with what Robert Martin calls **role interfaces** (as opposed to **header interfaces** that just mirror the implementation).

## Concrete shape

```java
// Defined where the admin panel lives — owned by the admin module
interface UserAdministration {
    void activateAccount(UserId id);
    void deleteAccount(UserId id);
    void assignRole(UserId id, Role role);
    AuditLog auditLogFor(UserId id);
}

// Defined where the password-reset handler lives
interface PasswordResetGateway {
    User findByEmail(Email email);
    void resetPassword(UserId id, PasswordResetToken token);
}

// Defined where the public profile page lives
interface PublicProfileQuery {
    PublicProfile profileFor(UserId id);
    boolean isProfilePublic(UserId id);
    List<Badge> badgesFor(UserId id);
}

// The implementation satisfies all roles. Consumers never see this type.
class UserService
    implements UserAdministration, PasswordResetGateway, PublicProfileQuery { ... }
```

Each consumer depends only on its narrow interface. The DI container wires the same `UserService` instance behind all three.

## Why this and not the alternatives

- **One fat `IUserService`**: violates ISP. The password-reset handler now transitively depends on `assignRole`, `deleteAccount`, etc. Mocking in tests forces stubs for methods the test doesn't care about. Recompilation/redeploy ripples spread further than they should.
- **One interface per method** (12 interfaces): over-segregation. ISP says "no client should depend on methods it does not use" — not "every method gets its own type". Group by **cohesive role the client plays**, not by method count.
- **Interfaces grouped by the implementation's internal taxonomy** (e.g. `IUserReader` + `IUserWriter` because that's how CQRS slices feel natural): also a trap. That's a header interface in disguise — it reflects how the *server* thinks about itself, not how *clients* use it. The admin panel doesn't want "all writes"; it wants "the admin operations".

## Two rules of thumb when drawing the lines

1. **Ownership lives with the client.** Each role interface is declared in (or near) the module that consumes it, not next to `UserService`. This is the dependency-inversion half of ISP — the high-level policy module owns the abstraction it depends on.
2. **One reason for a client to care.** If two methods are always used together by the same consumer and never separately, they belong on the same role interface. If the admin panel uses `activateAccount` but the password-reset flow never does, `activateAccount` does not go on `PasswordResetGateway`.

## Bonus: this also fixes the SRP smell you're hinting at

A class with 12 public methods spanning password reset, search, audit logs, and role assignment almost certainly violates SRP too — it has at least three reasons to change (auth team, admin team, profile team). The role-interface split is the **first step**; the second step, once the seams are visible, is to break the *implementation* apart into `AccountLifecycleService`, `CredentialService`, `ProfileQueryService`, etc., each implementing its own role interface(s). But ship the interface split first — it's safe, mechanical, and unblocks the consumers immediately.
