# Formatting Tooling for Kotlin/Spring

Martin's Ch. 5 ends with **Team Rules**: "A team of developers should agree upon a single formatting style, and then every member of that team should use that style." In 2026 this rule is implemented as a *file* (or several), not a wiki page. The file is the source of truth; the IDE reads it; the build verifies it; CI rejects violations. This document is the toolchain that encodes Martin's rules and the rules in `general-formatting-rules.md` / `kotlin-specific-formatting.md` / `spring-boot-formatting.md`.

---

## 1. The toolchain — pick once, use everywhere

| Tool | Role | Recommendation |
|---|---|---|
| **EditorConfig** | Cross-IDE / cross-tool baseline (indent, charset, final newline, trim whitespace) | **Always present.** One file `.editorconfig` at repo root. |
| **ktlint** | Kotlin formatter + linter implementing official Kotlin style guide. Highly configurable via `.editorconfig`. | **Default choice** for most Kotlin/Spring projects. |
| **ktfmt** | Google/Facebook formatter — deterministic, opinionated, very limited config. | Choose if your team values *no debates* over *Kotlin official style*. |
| **detekt** | Static analyzer with a formatting ruleset (delegates to ktlint internally). Adds smell detection beyond format. | Add alongside ktlint **for the lint rules**, disable its formatting if ktlint is already in place. |
| **diktat** | Alternative opinionated linter. Less common; mostly Russian Kotlin community. | Skip unless you have a specific reason. |
| **Spotless** | Gradle plugin that orchestrates formatters (ktlint, ktfmt, prettier, google-java-format, ...). Provides `check` and `apply` tasks. | **Default Gradle wrapper.** Use to run ktlint/ktfmt from Gradle uniformly. |
| **IntelliJ IDEA** | The IDE. Reads `.editorconfig`; can host ktlint via plugin. | Universal; configure once, share via VCS. |
| **pre-commit / lefthook / Husky** | Pre-commit hook framework. Runs the formatter before the commit lands. | **Recommended** to keep CI green. |

**Decision in one sentence**: start with **Spotless + ktlint + `.editorconfig` + lefthook + GitHub Actions gate**. Switch one component only when you have a concrete pain point.

---

## 2. `.editorconfig` — the universal baseline

`.editorconfig` is read by IntelliJ, ktlint, ktfmt, VS Code (with plugin), and most CLI tools. **Put it at the repo root.** This file is the canonical source for non-language-specific formatting.

```ini
# .editorconfig
root = true

[*]
charset                  = utf-8
end_of_line              = lf
insert_final_newline     = true
trim_trailing_whitespace = true
indent_style             = space
indent_size              = 4
max_line_length          = 120

[*.{kt,kts}]
ij_kotlin_imports_layout                                   = *
ij_kotlin_allow_trailing_comma                             = true
ij_kotlin_allow_trailing_comma_on_call_site                = true
ij_kotlin_packages_to_use_import_on_demand                 = org.assertj.core.api.Assertions,org.junit.jupiter.api.Assertions
ktlint_standard_no-wildcard-imports                        = enabled
ktlint_standard_filename                                   = enabled
ktlint_standard_property-naming                            = enabled
ktlint_standard_function-naming                            = enabled
ktlint_standard_max-line-length                            = enabled
ktlint_standard_trailing-comma-on-call-site                = enabled
ktlint_standard_trailing-comma-on-declaration-site         = enabled
ktlint_function_signature_body_expression_wrapping         = default

[*.{yml,yaml}]
indent_size = 2

[*.{json,md}]
indent_size = 2

[Makefile]
indent_style = tab
```

**Notes**:
- `ij_*` keys are read by IntelliJ.
- `ktlint_*` keys are read by ktlint (and detekt's formatting ruleset).
- `ij_kotlin_allow_trailing_comma = true` is the *enabling* switch; ktlint's `trailing-comma-on-declaration-site` is the *enforcing* switch.
- Two-space indent for YAML/JSON/Markdown is conventional.

---

## 3. ktlint — the default Kotlin formatter

### 3a. Why ktlint

- Implements the Kotlin official style guide.
- Configurable via `.editorconfig` — no separate config file.
- Has both `check` (CI gate) and `format` (auto-fix) modes.
- Plugin-light: works as a Gradle plugin (`org.jlleitschuh.gradle.ktlint`), a CLI binary, or via Spotless.

### 3b. Spotless + ktlint via Gradle

```kotlin
// build.gradle.kts (root or per-module)

plugins {
    id("com.diffplug.spotless") version "6.25.0"
}

spotless {
    kotlin {
        ktlint("1.2.1")  // pin a version
        target("**/*.kt")
        targetExclude("**/build/**", "**/generated/**")
        trimTrailingWhitespace()
        endWithNewline()
    }
    kotlinGradle {
        ktlint("1.2.1")
        target("*.gradle.kts", "**/*.gradle.kts")
    }
    yaml {
        target("**/*.yml", "**/*.yaml")
        targetExclude("**/build/**")
        jackson()
    }
}
```

Tasks:
- `./gradlew spotlessCheck` — fail if violations exist.
- `./gradlew spotlessApply` — auto-fix.

### 3c. Pin the formatter version

Every formatter version subtly differs. **Pin the version** in `build.gradle.kts` and CI, never use `+` or `latest`. Bump deliberately, in its own PR, with the resulting reformat in a follow-up `.git-blame-ignore-revs`-listed commit.

---

## 4. ktfmt — when determinism beats configurability

ktfmt is Facebook/Google's Kotlin formatter with three styles: `kotlinlang`, `google-style`, `meta-style`. Closer to "Black for Python" in spirit — very few knobs.

### 4a. When to pick ktfmt over ktlint

- The team is bikeshedding formatter config — ktfmt has almost no knobs to argue about.
- You want deterministic line-breaking (ktlint can produce subtly different output for the same input on different versions).
- Strict 100-char width is desired (ktfmt default).

### 4b. Spotless + ktfmt

```kotlin
spotless {
    kotlin {
        ktfmt("0.49").kotlinlangStyle()      // or .googleStyle() / .metaStyle()
        target("**/*.kt")
    }
}
```

### 4c. The tradeoff

ktfmt reformat is more aggressive: it may break/join lines you didn't want it to. If you adopt mid-project, expect a big-bang reformat PR. ktlint is gentler.

---

## 5. detekt — beyond formatting

detekt is a static analyzer; its `formatting` ruleset delegates to ktlint, so don't enable it if Spotless+ktlint is already running. Use detekt for *smell* rules beyond formatting:

```yaml
# detekt.yml — minimal config focused on smells, not formatting

complexity:
  LongMethod:
    threshold: 20
  LongParameterList:
    threshold: 4
  ComplexCondition:
    threshold: 4
  NestedBlockDepth:
    threshold: 3

style:
  WildcardImport:
    active: true
    excludeImports:
      - org.assertj.core.api.Assertions.*
      - org.junit.jupiter.api.Assertions.*
  ReturnCount:
    max: 2
  MagicNumber:
    active: false   # too noisy; tune to your taste
  ForbiddenComment:
    active: true
    values:
      - 'FIXME:'
      - 'STOPSHIP:'

formatting:
  active: false   # delegated to ktlint via Spotless
```

These thresholds are the **Clean Code numbers**: 20-line functions, 4 args, indent depth 3. detekt enforces in CI what `clean-code-functions` recommends in prose.

---

## 6. IntelliJ IDEA integration

### 6a. Auto-import from `.editorconfig`

IntelliJ reads `.editorconfig` automatically. To make sure it's wired:

`Settings → Editor → Code Style → Kotlin → tab "Set from..."` → choose **Kotlin style guide**. Then *enable* `EditorConfig support` (it usually is by default). The `.editorconfig` overrides win.

### 6b. ktlint IntelliJ plugin (optional)

The [ktlint plugin](https://plugins.jetbrains.com/plugin/15057-ktlint) runs ktlint on save and highlights violations in the editor. Removes the "I forgot to format" class of mistakes.

### 6c. Save Actions / Actions on Save

`Settings → Tools → Actions on Save` → enable `Reformat code` and `Optimize imports`. Combined with `.editorconfig`, every save is a tiny formatter pass.

### 6d. Don't commit `.idea/codeStyles/`

The `.editorconfig` is authoritative. Committing IntelliJ-specific code-style XML files is a smell — they duplicate `.editorconfig` and drift.

---

## 7. Pre-commit hook — catch drift locally

### 7a. lefthook (recommended for polyglot repos)

```yaml
# lefthook.yml
pre-commit:
  parallel: true
  commands:
    spotless:
      glob: "*.{kt,kts,yml,yaml}"
      run: ./gradlew spotlessCheck
    detekt:
      glob: "*.kt"
      run: ./gradlew detekt
```

Install: `lefthook install`.

### 7b. pre-commit (Python framework)

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: spotless
        name: Spotless check
        entry: ./gradlew spotlessCheck
        language: system
        types: [kotlin]
        pass_filenames: false
```

### 7c. Husky (Node-centric repos)

Mention only for completeness; lefthook or pre-commit are better fits for JVM repos.

### 7d. Auto-apply on commit vs. fail the commit

Two camps:
- **Fail the commit** — the developer must run `spotlessApply` and recommit. Surfaces formatter activity in the git log.
- **Auto-apply + re-stage** — the hook fixes and re-stages. More convenient; harder to notice when formatter changes are bundled with logic changes.

**Recommendation**: fail the commit. Reformat is a deliberate action, not a hidden mutation.

---

## 8. CI gate — the rule that matters

### 8a. GitHub Actions

```yaml
# .github/workflows/ci.yml
name: ci
on:
  push:
    branches: [main]
  pull_request:

jobs:
  format-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 21
      - uses: gradle/actions/setup-gradle@v3
      - run: ./gradlew spotlessCheck detekt

  build:
    runs-on: ubuntu-latest
    needs: format-check
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 21
      - uses: gradle/actions/setup-gradle@v3
      - run: ./gradlew check
```

**Conventions**:
- `format-check` is a **separate job** — it fails fast (< 30 sec) before the slower `build` job starts.
- `format-check` is **a required check** on `main` (Branch protection: Require status checks). Without "required", the gate doesn't exist.
- `./gradlew spotlessCheck detekt` runs both formatter check and lint check.

### 8b. GitLab / Bitbucket / etc.

Same shape: one job that runs `spotlessCheck`, blocking merge to `main`.

---

## 9. The first migration — big-bang reformat

When introducing a formatter to an established codebase:

### 9a. One PR, one commit

```bash
# On a fresh branch
./gradlew spotlessApply
git add -A
git commit -m "style: apply Spotless+ktlint formatting across the codebase"
```

**Don't** mix logic changes with the reformat. The reviewer needs to be able to scan the diff for nothing-but-whitespace.

### 9b. Add to `.git-blame-ignore-revs`

After merging the big-bang reformat commit:

```bash
# Record the commit's SHA in .git-blame-ignore-revs at repo root
echo "abc123def456...  # Big-bang Spotless+ktlint reformat 2026-05" >> .git-blame-ignore-revs

# Tell git blame to skip it
git config blame.ignoreRevsFile .git-blame-ignore-revs
```

Commit the file. `git blame` (and IntelliJ's blame, with the file configured) will skip the reformat commit, so you still see the author of the actual change underneath. GitHub also respects this file in the blame UI.

### 9c. Communicate the merge window

Notify the team. Anyone with an open feature branch needs to **merge or rebase** before the reformat hits `main`; afterward their branch's diff will be 100% conflicts. Don't reformat with active long-lived branches in flight without warning.

---

## 10. Tool version pinning

```kotlin
// build.gradle.kts — versions in one place
val ktlintVersion = "1.2.1"
val detektVersion = "1.23.6"
val spotlessVersion = "6.25.0"
```

**Why**:
- Reformatter version bumps produce noisy diffs. Pin and bump deliberately.
- CI must produce the same output as local. Floating versions break this.
- Major versions of ktlint/detekt change rule defaults; surprise upgrades break the gate.

**Bump cadence**: quarterly is a reasonable default. Bump in its own PR; the resulting reformat goes in a follow-up PR listed in `.git-blame-ignore-revs`.

---

## 11. Multi-module projects — apply once at root

For a multi-module Gradle project, configure Spotless at the **root** project so all modules share one config:

```kotlin
// root build.gradle.kts
plugins {
    id("com.diffplug.spotless") version "6.25.0" apply false
}

subprojects {
    apply(plugin = "com.diffplug.spotless")
    extensions.configure<com.diffplug.gradle.spotless.SpotlessExtension> {
        kotlin {
            ktlint("1.2.1")
            target("src/**/*.kt")
            targetExclude("**/build/**", "**/generated/**")
            trimTrailingWhitespace()
            endWithNewline()
        }
    }
}
```

Don't duplicate config per module. Don't let modules drift to different ktlint versions.

---

## 12. Generated code — exclude, don't fight

Spotless excludes:

```kotlin
spotless {
    kotlin {
        target("**/*.kt")
        targetExclude(
            "**/build/**",
            "**/generated/**",
            "**/build/generated/**",
            "**/generated-src/**",
            "**/openapi/generated/**",
        )
    }
}
```

kapt, Spring Modulith stub generators, MapStruct, OpenAPI client codegen — all produce output that has its own conventions. Excluding them keeps the formatter from churning every build.

---

## 13. Smell → fix quick reference (tooling layer)

| Symptom | Fix |
|---|---|
| `spotlessCheck` fails on CI; local was green | Pin the formatter version (CI and local on the same number); pin the JDK version (different JDKs → different file orderings). |
| `git blame` is dominated by the reformat commit | Add the reformat SHA to `.git-blame-ignore-revs`; configure `blame.ignoreRevsFile` locally and in CI tooling. |
| Developers keep forgetting to format | Add pre-commit hook (lefthook / pre-commit) that runs `spotlessCheck` and fails the commit. |
| IntelliJ and ktlint disagree about an edge case | The `.editorconfig` is authoritative; check which file IntelliJ is reading; install the ktlint IntelliJ plugin so the editor previews ktlint's output. |
| Spotless takes too long in CI | Run `spotlessCheck` and `build` as separate jobs; cache Gradle. The format check should finish in ≤ 30 s. |
| `detekt` flags things we want to allow | Tune `detekt.yml`, don't disable the ruleset. Disabling whole rulesets is the smell. |
| Wildcard imports keep coming back | Disable wildcard imports in IntelliJ: `Settings → Editor → Code Style → Kotlin → Imports → "Names count to use import with *"` → 999. Also enforce via ktlint `no-wildcard-imports`. |
| Trailing commas reverted on save | Ensure `ij_kotlin_allow_trailing_comma = true` and `ktlint trailing-comma-on-declaration-site = enabled` in `.editorconfig`. |
| One module formats differently | Spotless config is per-module; ensure it's applied via `subprojects { ... }` at root, not duplicated per module. |

---

## 14. Anti-patterns in tooling

- **Wiki-only formatting rules.** If the rules aren't in `.editorconfig` + ktlint, they don't exist. The first PR will violate them.
- **Optional CI gate.** A CI step that says "you should fix this" and is marked optional is theatre. Make it required, or remove it.
- **Per-developer code-style configs in `.idea/` committed to git.** They duplicate `.editorconfig` and drift over time. Delete; rely on `.editorconfig`.
- **Bumping ktlint without reformat.** A version bump that changes rules creates a sudden CI failure on any unrelated PR. Bump → reformat → merge → record in `.git-blame-ignore-revs`, all in close succession.
- **Mixing format and logic changes in one commit.** Even with `.git-blame-ignore-revs`, the PR review is unreadable. Two PRs.
- **Disabling Spotless "just for this file".** A single excluded file becomes a precedent. If a file genuinely can't be formatted, raise it for design discussion — usually the file shape is the smell, not the formatter.
- **Different formatter rules per profile** (e.g., production vs. test). One repo, one rule set. Tests are code.

---

## 15. The minimum viable setup — start here

For a fresh Kotlin/Spring project, the minimum credible formatting setup:

```
repo/
├── .editorconfig                  ← universal baseline
├── .git-blame-ignore-revs         ← grows over time
├── lefthook.yml                   ← pre-commit gate
├── build.gradle.kts               ← Spotless + ktlint + detekt
├── detekt.yml                     ← smell thresholds
└── .github/workflows/ci.yml       ← required CI gate
```

That's six files. With them in place, the team rules (Ch. 5) are enforced by tooling rather than memory.

---

## Cross-references

| Need | File |
|---|---|
| What rules the tooling is enforcing | `general-formatting-rules.md` |
| Kotlin-specific conventions the formatter applies | `kotlin-specific-formatting.md` |
| Spring application layout (assumes formatter is set up) | `spring-boot-formatting.md` |
| Why `karpathy-guidelines` §1 (surgical changes) interacts with the tooling | sibling skill `karpathy-guidelines` |
| Function-level smell thresholds that match detekt's defaults | sibling skill `clean-code-functions` |
