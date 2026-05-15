# OCP — Open-Closed

> A software artifact should be open for extension but closed for modification.

Martin calls this *"the most fundamental reason that we study software architecture."*

## What "closed" really means

"Closed for modification" ≠ frozen forever. It means closed against **the kinds of change extension is supposed to absorb**. New output channels shouldn't edit the use case; new business rules might. OCP doesn't require interfaces everywhere — only at boundaries where change must be absorbed.

## Two mechanisms

1. **Directional control** — pick which way source-code dependencies point so volatile code doesn't reach into stable code. DIP is the lever.
2. **Information hiding** — interfaces prevent transitive coupling. Even if A must call B, A should not see B's collaborators.

## Hierarchy of protection

Arrange so **higher-level components are protected from changes in lower-level components**. "Level" = distance from input/output; higher = more stable, closer to business rules.

## Red flags

- Adding a new output channel forces edits to domain classes.
- A DB schema change propagates up into use-case classes.
- A use-case class imports a web framework, ORM, or HTTP client directly.
- One file is touched by both "new feature" and "swap dependency" tasks — boundary missing.
