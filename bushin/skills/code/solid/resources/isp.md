# ISP — Interface Segregation Principle

## Definition

**"Clients should not be forced to depend on methods they do not use."**

Split fat interfaces so each client sees only what it actually calls.

## What it's NOT

- "ISP means many tiny interfaces." Not the point. Interfaces with no clients are noise. Segregate **by client role**, not by aesthetic.
- "ISP only matters in OO." No — modules, packages, and services have the same problem.

## Canonical example — the OPS class

`OPS` exposes `op1`, `op2`, `op3`. `User1` calls only `op1`; `User2` only `op2`; `User3` only `op3`. In a statically typed language every user imports `OPS` and is therefore transitively coupled to the source files behind `op2` and `op3` — recompilation, redeployment, and accidental breakage propagate to clients that don't care.

The fix: define `Op1`, `Op2`, `Op3`, each scoped to one client role. `OPS` implements all three. Each user depends only on its own interface.

## Language reading vs. architectural reading

Martin: "ISP is a language issue rather than an architecture issue" — at code level the cost is recompilation and redeployment, and dynamically typed languages don't pay it. **But** the principle also reads at the architectural scale:

> System `S` depends on framework `F`, which depends on database `D`. `S` doesn't use `D` directly. A change in `D` that `S` never touches still forces `F` to redeploy, which forces `S` to redeploy. The dependency edge exists, so it costs.

Generalize: **avoid depending on things that contain more than you need**, at every scale — class, module, service, deployable.

## Anti-pattern

```kotlin
interface AllOps {
    fun op1()
    fun op2()
    fun op3()
}

class OpsImpl : AllOps {
    override fun op1() { /* ... */ }
    override fun op2() { /* ... */ }
    override fun op3() { /* ... */ }
}

class User1(private val ops: AllOps) {
    fun go() = ops.op1()                  // imports op2, op3 along for the ride
}
```

## Good pattern

```kotlin
interface Op1 { fun op1() }
interface Op2 { fun op2() }
interface Op3 { fun op3() }

class OpsImpl : Op1, Op2, Op3 {
    override fun op1() { /* ... */ }
    override fun op2() { /* ... */ }
    override fun op3() { /* ... */ }
}

class User1(private val op: Op1) {
    fun go() = op.op1()                   // depends on exactly what it uses
}
```

## Red flags

- A class implements an interface but no-ops or throws on half the methods.
- A consumer needs 2 of an interface's 12 methods.
- A test double has to stub methods the system under test never calls.
- A heavy dependency is pulled in to use one corner of it.
- A single "header interface" exists where role-specific interfaces would fit each client.
