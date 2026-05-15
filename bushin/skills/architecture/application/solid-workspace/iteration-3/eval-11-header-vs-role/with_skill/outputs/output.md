# Structuring `UserService` for ISP

Classic ISP smell: one class, 12 methods, three consumers that each touch a different corner. The fix isn't "split `UserService` into many classes" — it's **segregate the contracts by client role**, while letting the implementation stay cohesive.

## Don't do this (header interface)

```kotlin
interface UserService {           // mirrors the impl 1:1
    fun resetPassword(...)
    fun searchUsers(...)
    fun activateAccount(...)
    fun deleteUser(...)
    fun updateProfile(...)
    fun assignRole(...)
    fun readAuditLog(...)
    // … 12 in total
}

class UserServiceImpl : UserService { ... }
```

Every consumer now depends on every method. The password-reset handler sees `assignRole` and `readAuditLog`. Mocks in its tests have to stub methods it never calls. A change to the audit-log signature forces the password-reset module to recompile/redeploy. That's the dependency edge ISP is about — it exists, so it costs.

## Do this (role interfaces, one impl)

Define interfaces **from each client's perspective**, named after the role:

```kotlin
interface PasswordResetter {
    fun requestReset(email: String)
    fun completeReset(token: String, newPassword: String)
}

interface UserSearcher {
    fun findByQuery(q: String): List<UserSummary>
}

interface PublicProfileReader {
    fun getProfile(userId: UserId): PublicProfile
    fun listRecentActivity(userId: UserId): List<Activity>
    fun getAvatarUrl(userId: UserId): String
}

interface UserAdministration {              // the admin-panel role
    fun activateAccount(userId: UserId)
    fun deleteUser(userId: UserId)
    fun assignRole(userId: UserId, role: Role)
    fun readAuditLog(userId: UserId): AuditLog
}

interface ProfileEditor {
    fun updateProfile(userId: UserId, patch: ProfilePatch)
}
```

Then **one cohesive implementation** wears all the hats:

```kotlin
class UserService :
    PasswordResetter,
    UserSearcher,
    PublicProfileReader,
    UserAdministration,
    ProfileEditor { ... }
```

Consumers depend only on the role they use:

```kotlin
class PasswordResetEmailHandler(private val resetter: PasswordResetter) { ... }
class AdminPanelController(private val admin: UserAdministration, private val search: UserSearcher) { ... }
class PublicProfileController(private val profiles: PublicProfileReader) { ... }
```

DI wires the same `UserService` instance into every slot.

## Why this and not "split the class"

ISP is a rule about **contracts**, not implementations. Splitting `UserServiceImpl` into five classes is an SRP question (different actors? different reasons to change?) and you answer it separately. If password reset, search, admin operations, and profile editing all answer to the same actor (say, the identity team) and share state/transactions, keep them in one class. The role interfaces give clients a narrow view without fragmenting the implementation.

If two of those interface groups actually answer to different actors — e.g. audit-log access is owned by the compliance team while password reset is owned by the identity team — that's the cue to also split the impl. Then SRP and ISP align: one actor, one class, one role interface per outside view.

## Concrete recommendation

1. Define five role interfaces named after the consumers' verbs: `PasswordResetter`, `UserSearcher`, `PublicProfileReader`, `UserAdministration`, `ProfileEditor`. Each lists only the methods that role's clients call.
2. Keep `UserService` as one class implementing all five. Don't pre-split until you have an SRP reason (different actors, different change cadence, real coupling pain).
3. Inject the **role**, never the class, into each consumer. `PasswordResetEmailHandler` takes `PasswordResetter`, not `UserService`.
4. Delete any header `UserService` interface that mirrors the impl 1:1 — it's noise that re-creates the very coupling you're trying to remove.
5. Sanity check: any test double for a consumer should only need to stub the 1–3 methods on its role interface. If you're still stubbing 12 methods to test the password-reset flow, the segregation didn't land.

The smell to watch for going forward: the moment a new consumer wants a method that doesn't fit any existing role, add a new role interface (or extend the most-fitting one). Don't widen `UserAdministration` to absorb unrelated needs — that's how header interfaces grow back.
