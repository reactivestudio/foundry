# dmitriy-claude

Personal Claude Code marketplace. Migrates the contents of `~/.claude/skills/` and `~/.claude/agents/` into 7 granular plugins so only the ones needed for the current task consume context.

## Plugins

| Plugin | Contents | Enable when |
|---|---|---|
| `methodology` | methodology, methodology-clarifying-questions, methodology-verification, debugging-systematic | always |
| `clean-code` | clean-code router + 9 per-topic siblings (naming, functions, classes, comments, formatting, error-handling, boundaries, objects-and-data, systems) | refactoring, code review |
| `spring` | spring router + spring-aop, spring-bean, spring-boot, spring-boot-mastery, spring-events, spring-security-and-auth, spring-transactions, spring-validation, spring-web-mvc, caching-strategies-spring, messaging-rabbitmq-spring | Spring projects |
| `ddd` | ddd router + ddd-context-mapping, ddd-strategic-design, ddd-tactical-patterns | DDD projects |
| `test` | test router + test-acceptance, test-architecture, test-contract, test-integration, test-principles, test-strategy, test-unit | test work |
| `architecture` | architecture, architecture-decision-records, architecture-patterns, architect-review, solid-principles, grasp-patterns, gof-patterns, system-design-fundamentals, microservices-patterns-deep, api-design-principles, database-design, algorithms-applied-backend, jvm-performance, cqrs-implementation | system design |
| `agents` | architect, architecture-reviewer, code-implementor, code-reviewer, security-reviewer, test-architect, test-implementor, test-reviewer, troubleshooter | as needed |

## Install

Add this marketplace and enable plugins in `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "dmitriy-claude": {
      "source": {
        "source": "github",
        "repo": "reactivestudio/claude"
      }
    }
  },
  "enabledPlugins": {
    "methodology@dmitriy-claude": true,
    "clean-code@dmitriy-claude": false,
    "spring@dmitriy-claude": false,
    "ddd@dmitriy-claude": false,
    "test@dmitriy-claude": false,
    "architecture@dmitriy-claude": false,
    "agents@dmitriy-claude": false
  }
}
```

Toggle plugins on/off per project as needed. Each plugin you disable removes its skill descriptions from the in-prompt index — saves several thousand tokens for stacks you're not working in.

## Layout

```
.
├── .claude-plugin/
│   └── marketplace.json
├── plugins/
│   ├── methodology/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/<skill>/SKILL.md
│   ├── clean-code/...
│   ├── spring/...
│   ├── ddd/...
│   ├── test/...
│   ├── architecture/...
│   └── agents/
│       ├── .claude-plugin/plugin.json
│       └── agents/<agent>.md
└── README.md
```

Skills/agents are auto-discovered from `skills/` and `agents/` directories — no need to list them in `plugin.json`.
