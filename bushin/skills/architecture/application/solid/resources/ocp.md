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

## Level confusion (looks like extension, isn't)

A new UI feature is not a new instance of a data-export strategy. Different distance from I/O = different level = different module. Forcing them into one hierarchy makes the supertype a lie.

Example: an `OrderExporter` hierarchy (Excel/PDF/CSV) serves a use-case actor producing data files for download. A "capture current screen as image" button serves a UI actor and lives closer to I/O — viewport, pixels, frame buffer. `ScreenshotExporter : OrderExporter` would make `export(orders): ByteArray` meaningless for the screenshot case (which order list? why?), and callers would have to special-case it again. Different level, different module — not a new subclass.

**Diagnostic.** If the only thing your subtypes share is "they all return `ByteArray`" or "they all produce some output," you don't have a contract — you have a return type. A real contract carries meaning: what the bytes mean, what the input must be, what the caller can rely on. If you can't state that meaning without referring to the specific subtype, the abstraction is forced.

## Red flags

- Adding a new output channel forces edits to domain classes.
- A DB schema change propagates up into use-case classes.
- A use-case class imports a web framework, ORM, or HTTP client directly.
- One file is touched by both "new feature" and "swap dependency" tasks — boundary missing.
- A new UI feature gets shoved into an export / strategy hierarchy because both "produce output" — level confusion.
