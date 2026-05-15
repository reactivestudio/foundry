# REST vs gRPC — decision frame

Load when picking the protocol for a new boundary, or when challenged on an
existing one. The body's quick-frame is the summary; this is the reasoning.

## The axes that actually decide

| Axis | REST + JSON | gRPC + Protobuf |
|---|---|---|
| **Audience** | External developers, browsers, partner integrations. | Internal services, polyglot teams, generated clients. |
| **Debuggability** | curl, browser, any HTTP tool. Logs are readable. | `grpcurl` works but is heavier. Binary on the wire — logs less human-friendly. |
| **Schema enforcement** | OpenAPI is descriptive; runtime is loose. | `.proto` is enforced by the compiler. Field numbers are immutable. |
| **Streaming** | SSE / WebSocket exist but are bolt-ons. | First-class server / client / bidi streaming. |
| **Latency / payload size** | JSON parse + verbose field names. | Binary, generally 3-5× smaller and faster to parse. |
| **Browser reach** | Native. | Needs gRPC-Web + proxy. Caveats apply. |
| **Tooling maturity** | Universal. Every language, every editor. | Strong in Go / Java / Kotlin / C++. Weaker in some scripting langs. |
| **Versioning ergonomics** | URL prefix + breaking-change discipline. | Package version + immutable field numbers (mistakes get caught at build). |

## Default heuristic

- **External, partner, browser, "we don't know who'll call this"** → REST.
- **Internal, high-volume, "we own all clients", or streaming** → gRPC.
- **Polyglot internal (Go talks to Python talks to Kotlin)** → gRPC strongly
  preferred — one `.proto`, generated clients in every language.

## Combining — common and correct

```
[ browser ] --REST/JSON--> [ edge BFF ] --gRPC--> [ services ]
[ partner ] --REST/JSON--> [ edge API ]
                            |
                            +--gRPC--> [ services ]
```

The decision is per-boundary, not per-system. The edge layer translates;
that's its job. Don't push gRPC to the browser unless you've already
weighed gRPC-Web.

## When neither is the right answer

| Symptom | Probably want | Why |
|---|---|---|
| Caller doesn't need the answer in this call | Messaging / events | See `messaging-boundary.md`. |
| Multi-shape reads from many heterogeneous clients (BFF candidate) | A focused REST endpoint per consumer, or a BFF | GraphQL is the obvious tool but is out of scope here. |
| Browser real-time push with simple back-channel | SSE | Cheap, REST-native, one-way is enough. |
| Browser real-time push with rich back-channel | WebSocket | When you need full duplex from the browser. |

## Migration patterns

If you have REST and want to add gRPC:
- Run both in parallel. The `.proto` and the OpenAPI describe *the same*
  domain operations; map field-for-field where they overlap.
- New features land in gRPC first (cheaper to evolve); back-port to REST
  only if external consumers need it.

If you have gRPC and need a REST edge:
- `grpc-gateway` / Spring's gRPC-to-REST starters can autogenerate REST
  from `.proto` with annotations. Useful for read endpoints; less so for
  anything with rich error semantics.
