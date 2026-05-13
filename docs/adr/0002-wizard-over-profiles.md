# ADR 0002 — Interactive wizard over YAML profiles

- **Status:** Accepted
- **Date:** 2026-05-13
- **Deciders:** repo owner (solo)

## Context

Given the symlink mechanism (ADR 0001), we needed a way for the user to declare *which* components to link for a given project. Options considered:

1. **Composable YAML profiles** — `profiles/spring-boot.yaml`, `profiles/ddd.yaml`, etc., invoked as `claude-link install --profile spring-boot --profile ddd`. Profiles are manifests listing components; multiple profiles compose additively.
2. **Interactive wizard** — `claude-init` asks questions ("Is this Spring Boot? DDD? heavy testing?") and toggles component selection accordingly.
3. **Per-component CLI** — `claude-link add agent code-reviewer`, `claude-link add command /review`, no bundles.

## Decision

Use **interactive wizard** (`claude-init`).

## Rationale

The user is solo and the number of distinct project setups is small. Profiles introduce a layer of abstraction (YAML manifests, composition rules, parser dependency on `yq`) whose value is *reuse of a named bundle across projects*. With one user and ~5 distinct project archetypes, that reuse benefit is marginal.

Trade-offs:

| Factor | Profiles | Wizard (chosen) | Per-component |
|---|---|---|---|
| First-run cognitive load | "which profiles exist?" | guided | "which components exist?" |
| Maintenance burden (adding components) | update profile YAMLs | update wizard logic | none |
| Required dependencies | `yq` + `jq` | `jq` only | `jq` only |
| Composition of multiple stacks | explicit (`--profile a --profile b`) | implicit (toggle within wizard) | manual |
| Self-documenting | no (need `docs/profiles.md`) | yes (questions explain themselves) | no |
| Re-run after stack change | edit profile or re-invoke | `--reconfigure` | manual deltas |

The wizard's UX is: *"the user looks at the project and answers questions"*. This is exactly what the user requested ("я смотрю что за проект и выбираю нужные") and exactly what a profile system would force into an upfront declaration.

## Consequences

- No `profiles/` directory in the repo.
- The wizard's question set is the source of truth for what stacks are supported. Adding a new stack means adding questions to the wizard, not creating new YAML files.
- `claude-init --reconfigure` replaces the "swap profiles" workflow.
- No `yq` dependency.
- Documenting "what got installed" is done at run time (summary) — there's no manifest to point at after the fact.

## Reconsider when

- More than 8–10 distinct project archetypes emerge, making wizard questions repetitive.
- Multiple users want to share a "team standard" setup that should be applied identically across machines.
- A non-interactive mode is needed (CI, scripted bootstrap of many projects).
