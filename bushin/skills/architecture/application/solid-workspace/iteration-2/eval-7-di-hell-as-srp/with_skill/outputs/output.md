No. ServiceLocator and builders hide the symptom; they don't touch the cause. A 9-arg constructor is almost always an **SRP** smell, not a DI/wiring smell.

## Diagnosis

Nine collaborators means `ReportGenerator` is plausibly answering to several different actors at once. Run the actor test before anything else — list the stakeholders who file change requests against this class:

- Finance wants a new column or rounding rule? (one actor)
- Ops wants a different delivery channel or schedule? (another)
- Compliance wants an audit trail or retention policy? (another)
- A platform team owns the logger/config plumbing? (incidental — not an actor)

If two or more business actors show up, the parameter list is a *receipt* for an SRP violation. Hiding it behind a locator just makes the receipt harder to read; the class still answers to multiple masters, merge hotspots and accidental duplication still follow.

## Why ServiceLocator / Builder is the wrong fix

- **ServiceLocator**: trades explicit dependencies for hidden ones. The class still depends on all 9 things; you've just made that fact invisible to the compiler and to PR reviewers. Tests get worse, not better. Actor count: unchanged.
- **Builder**: cosmetic. Same dependencies, prettier call site. Actor count: unchanged.

Both treat "long constructor" as the disease. It's the thermometer.

## What to do instead

1. **Map the methods of `ReportGenerator` to actors.** Which method exists because *whom* asks for it?
2. **Split along the actor seams.** Likely shape: `ReportDataLoader` (talks to the repositories), `ReportComposer` (pure business policy — formatting, totals, rules), `ReportDeliverer` (channels/IO). Each gets only the collaborators it actually needs — typically 2–3, not 9.
3. **Pass a passive data carrier between them** (`ReportData` / `ReportDraft`) instead of sharing the repos around.
4. **If callers want one entry point**, wrap the trio in a thin `ReportFacade`. That's convenience, not a return to the god class.
5. **Logger and config** are infra, not actors — they often disappear from most of the split classes, or get injected only where genuinely used.

After the split, each constructor shrinks on its own. No locator needed.

## Caveat — when *not* to split

If you check and there's genuinely **one actor** today (e.g., only Finance owns every method) and no second actor on the roadmap, don't split speculatively. In that narrow case, the 9 params are honest — and the right move is to look for true infra noise to collapse (e.g., bundle related repos behind a domain-owned interface per DIP), not to invent fake seams. But that's the rare answer. With 5 repos + 2 services in one class, multiple actors is the strong prior.

## Recommendation

Reject the ServiceLocator/Builder suggestion. Do the actor mapping, then split. The parameter count is feedback from the design — listen to it, don't muffle it.
