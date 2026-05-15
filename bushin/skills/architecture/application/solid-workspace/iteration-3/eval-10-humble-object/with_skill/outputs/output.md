Yes — this is the textbook case for **Humble Object**, the LSP escape hatch for "subtype has to violate the contract because the framework dictates inheritance."

## What you're describing

`BaseController.initialize()` has a contract. Your override weakens its postconditions (and probably strengthens preconditions: "must be called inside a live JavaFX lifecycle with a stage attached"). Callers written against `BaseController` can't substitute your subclass in a test without it throwing. That's LSP broken in both classic ways at once — and you can't fix it by changing the parent, because you don't own the framework.

## The fix: split the class in two

- **Humble shell** — the controller that still extends `BaseController`. Keep it thin: wire up FX nodes, observe framework lifecycle, forward events. It's allowed to be hard to test and allowed to fail outside a real FX context — that's honest, because *that's what the framework's contract actually requires*. No business logic lives here.
- **Plain object** — a framework-free class holding all the logic that used to clutter `initialize()`. No JavaFX imports, no lifecycle assumptions, plain method calls with plain inputs/outputs. This is what your tests target. LSP-clean because it implements no foreign contract it can't honor.

The shell's `initialize()` becomes a one-liner: build inputs from FX state, delegate to the plain object, apply the result back to FX nodes.

## Why this is the SOLID-aligned answer, not a workaround

- **LSP** — you stop pretending the controller subtype is substitutable. The unavoidable violation is **quarantined at the framework seam** instead of leaking into your logic. The plain object *is* substitutable, because you designed its contract.
- **SRP** — two actors were sharing one file: the FX framework (lifecycle, threading) and your domain (whatever the controller actually decides). Humble Object splits along that actor seam.
- **DIP** — your logic stops depending on a volatile framework base class. The arrow now points the other way: the FX-bound shell depends on your stable plain object, not vice versa.

## Concrete recommendation

1. List everything `initialize()` currently does. Tag each line as **framework wiring** (touches `@FXML` fields, `Platform.runLater`, scene/stage, listeners) or **logic** (decisions, state transitions, formatting, validation).
2. Move the **logic** lines into a new plain class — name it after what it *does*, not after the controller. Give it a narrow interface the controller can call. No JavaFX types in its signatures; pass primitives, domain objects, or small DTOs.
3. In the controller's `initialize()`: read FX state into those plain inputs, call the plain object, write results back to FX nodes. That's it.
4. Write unit tests against the plain object only. Leave the shell uncovered or covered by a thin FX integration test — that's the correct trade, not a gap.

If you find the shell still has branching logic after step 3, you haven't pulled enough out — keep going until the shell is dumb.

## When this is *not* the right move

If `initialize()` is genuinely only framework wiring (no decisions, no state), there's nothing to extract — leave it. Humble Object is for the case you described, where logic is trapped behind a contract you can't honor.
