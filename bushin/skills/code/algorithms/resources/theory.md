# Theory — Nuance Worth Carrying

This file is intentionally short. Standard Big-O reasoning, complexity-class tables, and collection-cost cheat sheets are training-corpus material — Claude has them already. What follows is the residue: small, specific points that change behaviour and don't restate baseline knowledge.

## Same operation, different container

The same-looking call can be O(1) or O(N) depending on the type. The ones that bite:

- `List.size()` O(1) vs **`Iterable.count()` O(N)** — accepting an `Iterable` parameter and calling `count()` is a hidden scan.
- `List.last()` O(1) on `ArrayList` vs **O(N) on `Sequence`** — chaining `.last()` after `asSequence()` defeats laziness.
- `Map.containsKey` O(1) on `HashMap` vs **O(log N) on `TreeMap`** vs **O(N) for `containsValue` on any map**.
- `List.removeAt(0)` O(N) on `ArrayList` vs O(1) on `ArrayDeque`.

In a hot loop, read the declared parameter type, not the variable name. The cost depends on what was *passed in*, not what the name suggests.

## Lazy is an allocation axis, not a time axis

A chain over a `List` allocates an intermediate `List` at each step. Over a `Sequence`, one. **Time complexity is the same.** This is the most common Sequence misconception.

`.asSequence()` wins only when *all three* hold: ≥3 steps in the chain, input large (~1K+), and early termination (`first`, `take`, `any`). Below those bars, eager is faster and clearer — and `.asSequence()` in existing code should be **removed**, not preserved. See [kotlin.md](kotlin.md) for the active-removal pattern.

## Algorithms and data structures are one decision

"Switch `List` to `Set`" *is* the algorithm change, even though no logic moved. Most algorithm improvements in backend code are one-line container edits.

Corollary: if `list.contains` shows up in a loop body, the algorithm is wrong *because the container is wrong*. Look at the container first, before designing a new algorithm.
