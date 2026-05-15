# ISP — Interface Segregation

> Clients should not be forced to depend on methods they do not use.

## What baseline gets wrong

- **"ISP means many small interfaces."** No — interfaces without clients are noise. Segregate **by client role**, not by aesthetic.
- **"ISP is only OO."** No — modules, packages, services, and deployables have the same cost.

## Scope beyond OO

The architectural reading:

> System `S` depends on framework `F`, which depends on database `D`. `S` doesn't use `D` directly. A change in `D` still forces `F` to redeploy, which forces `S` to redeploy. The dependency edge exists, so it costs.

Generalize: **avoid depending on things that contain more than you need**, at every scale — class, module, service, deployable.

## Red flags

- A class implements an interface but no-ops or throws on half the methods.
- A consumer needs 2 of an interface's 12 methods.
- A test double has to stub methods the SUT never calls.
- A heavy dependency is pulled in to use one corner of it.
