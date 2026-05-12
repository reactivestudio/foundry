# Y-Statement Template

A single-paragraph ADR. Useful when the entire decision fits in one sentence-shaped structure and a multi-section format would be ceremony. Originally proposed by Olaf Zimmermann.

Best for: communicating a decision in a Slack message, a meeting summary, or a roadmap bullet without losing the trade-off.

## The structure

```markdown
# ADR-NNNN: <title>

In the context of **<use case / system / situation>**,
facing **<concern / problem / forcing function>**,
we decided for **<chosen option>**
and against **<the most credible alternatives, with one-line why-not>**,
to achieve **<quality attribute / benefit / driver served>**,
accepting that **<the trade-off we'll pay>**.
```

## Worked example

```markdown
# ADR-0015: API Gateway Selection

In the context of **building a microservices architecture**,
facing **the need for centralized API management, authentication, and rate limiting**,
we decided for **Kong Gateway**
and against **AWS API Gateway (vendor lock-in) and custom Nginx solution (no plugin ecosystem)**,
to achieve **vendor independence, plugin extensibility, and team familiarity with Lua**,
accepting that **we need to manage Kong infrastructure ourselves**.
```

## When this format earns its keep

- Decisions where the *shape* of the trade-off is the message, more than the procedural detail.
- Quick decisions where the alternative would be no ADR at all — and a Y-statement is far better than nothing.
- Sharing a decision in chat or email without writing a long-form document.

## When NOT to use this

- The decision is irreversible (one-way door). Use `madr.md` — Y-statements are too compressed to be defensible six months later.
- More than two alternatives need to be compared. The format breaks past that.
- Compliance / regulatory audit may want to see the decision. Use `madr.md` with full rationale and named deciders.
- The "accepting that…" clause would need 50 words. If the trade-off is that big, use the full template.
