# No. Don't split.

This is textbook **speculative SRP** — splitting "to follow SRP" without a second actor on the horizon.

## Why the proposal is wrong

SRP isn't "one method per class" or "one verb per class." Martin's wording:

> A module should be responsible to **one, and only one, actor.**

An actor is a group of stakeholders who request the same kinds of changes. Count actors, not methods.

Your `UserService`:
- `register()`, `login()`, `updateProfile()`, `deleteAccount()`
- All four maintained by **one team** (auth)
- All four answer to the same stakeholder — whoever owns the user-account lifecycle

That's **one actor**. SRP says: leave it alone.

## What splitting actually costs you

Speculative splits punish you:

- Four files instead of one — more navigation, more imports, more wiring.
- The same change request ("add 2FA," "add audit logging on every account-state transition") still touches all four classes. You haven't reduced change surface; you've spread it across more files.
- If a shared helper exists (password hashing, session token issuance, audit emission), you now have to decide whether to extract it to a fifth class or duplicate it. Both choices are worse than "private method on `UserService`."
- DI graph gets noisier — four beans/registrations where one sufficed.

You're paying real cost for a benefit that hasn't shown up.

## When to revisit

Split when a **second actor actually arrives**, and split along the seam that actor reveals — not the seam the new engineer guessed at. Concrete triggers:

- A compliance/security team starts requesting changes to `deleteAccount()` (GDPR erasure, retention policy) that are orthogonal to what the auth team wants for `login()`. Now `deleteAccount` answers to two masters → split.
- A growth team owns `register()` (funnel experiments, referral codes) while auth owns `login()`. Two teams landing PRs on the same file every sprint → split.
- Merge conflicts on `UserService` start recurring across teams.

None of that has happened. The new engineer is pattern-matching on method count, not actor count.

## What to tell the engineer

"SRP is about who requests changes, not how many methods a class has. All four methods answer to our team today. If a second stakeholder shows up later — compliance wanting custom deletion, growth wanting custom registration — we'll split along *that* seam, which we can't predict from here. Splitting now locks in guesses; splitting later locks in evidence."

If `UserService` is genuinely getting unwieldy (5+ collaborators in the constructor, or a single method doing too much), that's a **function-level** problem — extract private methods or a helper, don't shard the class.

## Recommendation

Keep `UserService` as one class. Revisit if and when a second actor files a change request that pulls one of those four methods in a direction the other three don't want to go.
