# gRPC + protobuf specifics

Load when writing or evolving a `.proto`. Examples in plain `.proto` syntax;
Kotlin server glue lives in `spring.md` (Spring-bound) and
`kotlin-idioms.md` (idiomatic patterns).

## File layout

```protobuf
// proto/user/v1/user.proto
syntax = "proto3";

package com.example.user.v1;

option java_multiple_files = true;
option java_package = "com.example.user.v1";

import "google/protobuf/timestamp.proto";
import "google/protobuf/field_mask.proto";
import "google/protobuf/empty.proto";

service UserService {
  rpc GetUser    (GetUserRequest)    returns (User);
  rpc ListUsers  (ListUsersRequest)  returns (ListUsersResponse);
  rpc CreateUser (CreateUserRequest) returns (User);
  rpc UpdateUser (UpdateUserRequest) returns (User);
  rpc DeleteUser (DeleteUserRequest) returns (google.protobuf.Empty);

  rpc WatchUsers (WatchUsersRequest) returns (stream UserEvent);
  rpc BulkCreate (stream CreateUserRequest) returns (BulkCreateResponse);
}
```

Package version (`v1`) is the API version. New major version → new package,
new file, new service.

## Messages — field-number rules

```protobuf
message User {
  string                    id         = 1;
  string                    email      = 2;
  string                    name       = 3;
  google.protobuf.Timestamp created_at = 4;
  bool                      is_active  = 5;

  reserved 6, 7;                // removed fields — never reuse
  reserved "old_name_field";    // also reserve names if you renamed
}
```

Three hard rules:

1. **Field numbers `1`–`15` encode in one byte.** Reserve them for hot
   fields (everything read on every request).
2. **Never reuse a field number.** Old clients silently decode the new
   field's bytes as the old field. Data corruption. Mark removed numbers
   `reserved`.
3. **Add new fields only as optional.** Never repurpose an existing field's
   meaning. If meaning must change, allocate a new field number.

## Enums — `_UNSPECIFIED = 0` always

```protobuf
enum UserStatus {
  USER_STATUS_UNSPECIFIED = 0;  // default for unset → caught at validation
  USER_STATUS_ACTIVE      = 1;
  USER_STATUS_SUSPENDED   = 2;
  USER_STATUS_DELETED     = 3;
}
```

Proto3 default-initialises every field. If `0` is `ACTIVE`, every
default-constructed message looks "active" — silent semantic errors. Make
`0` the sentinel and reject it in your validator.

## Well-known types — use them

| Need | Use |
|---|---|
| Timestamp | `google.protobuf.Timestamp` |
| Duration | `google.protobuf.Duration` |
| Partial update mask | `google.protobuf.FieldMask` |
| "No payload" return | `google.protobuf.Empty` |
| Untyped value | `google.protobuf.Any` (rarely; prefer a typed message) |
| Optional primitives | `google.protobuf.StringValue` / `Int32Value` / … (proto3 lacks `optional` for primitives — wrappers are the workaround) |

Don't reinvent these.

## Pagination — cursor-based, Google AIP-158

```protobuf
message ListUsersRequest {
  int32  page_size  = 1;        // server caps; 0 = use default
  string page_token = 2;        // opaque; from previous response
  string filter     = 3;        // AIP-160 expression, optional
  string order_by   = 4;        // AIP-132 expression, optional
}

message ListUsersResponse {
  repeated User users           = 1;
  string        next_page_token = 2;   // empty when no more pages
}
```

Skip `total_count` unless the dataset is small and you've measured the cost
of computing it.

## Partial updates — `FieldMask`, not optional fields

```protobuf
message UpdateUserRequest {
  string                    id          = 1;
  User                      user        = 2;
  google.protobuf.FieldMask update_mask = 3;  // ["email", "name"]
}
```

Server reads `update_mask` and applies only those paths from `user`. Lets
you distinguish "set to empty string" from "don't touch this field" —
proto3 can't otherwise.

## Streaming — four kinds, one rule

| Kind | Use |
|---|---|
| Unary | Default request/response |
| Server streaming | Watch APIs, subscriptions, long-running events |
| Client streaming | Bulk upload, log shipping, sensor data with backpressure |
| Bidirectional | Interactive sessions (chat, collab editing) |

Streaming rules:

- **Client always sets a deadline.** Without one, the RPC hangs forever on
  the network. `withDeadlineAfter(30, SECONDS)`.
- **Long server streams need a heartbeat.** Otherwise the client can't tell
  "server is busy" from "server died". A periodic empty event or a
  keepalive message works.
- **Cancellation must clean up resources.** When the client disconnects, the
  collector cancels; ensure DB cursors, queue consumers, and file handles
  close. Don't leak per-stream resources.

## Versioning — package, not field

- Breaking change → new package: `com.example.user.v2`. New file, new
  service, new generated client. Run `v1` and `v2` in parallel for the
  migration window.
- Non-breaking change (new optional field, new method) → stay in `v1`.
- Deprecate old methods with `option deprecated = true;` and a sunset note
  in comments.

## Status mapping — see `errors.md`

Canonical mapping from domain situation to gRPC `Status` (the 16 codes)
lives in `errors.md` to avoid duplication with REST status semantics.

## Bulk operations

Two viable patterns:

1. **Client-streaming RPC** — caller streams `N` create requests; server
   responds once with a summary. Backpressure-friendly. See `BulkCreate`
   above.
2. **Single RPC with `repeated`** — caller sends a batch, server returns
   per-item results. Simpler to code, no backpressure. AIP-231 colon syntax
   doesn't apply to gRPC; the method name (`BatchCreateUsers`) is the cue.
