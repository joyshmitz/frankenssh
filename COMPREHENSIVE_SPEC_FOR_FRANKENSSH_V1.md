# COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1

> Canonical normative specification for FrankenSSH V1.
> If this document conflicts with `README.md`, `PLAN_TO_PORT_SSH_TO_RUST.md`,
> `PROPOSED_ARCHITECTURE.md`, `EXISTING_SSH_STRUCTURE.md`, or
> `FRANKENSSH_PROPOSAL.md`, this document is authoritative.

## 0. Prime Directive

FrankenSSH MUST be wire-compatible with SSH-2 peers in the OpenSSH ecosystem
for the scoped feature set in this specification.

Compatibility with OpenSSH is a hard constraint, not an aspirational goal.
If an implementation choice conflicts with observed OpenSSH behavior in strict
mode for an in-scope feature, the implementation is incorrect until the
divergence is explicitly documented and accepted in this specification.

## 1. Normative Language

The key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
RECOMMENDED, MAY, and OPTIONAL are to be interpreted as described in RFC 2119.

Normative references include:

1. RFC 4251, RFC 4252, RFC 4253, RFC 4254 (core SSH-2)
2. RFC 5656 (ECDH), RFC 8308 (extension negotiation)
3. draft-ietf-sshm-pq-ssh (PQ SSH KEX guidance)
4. draft-ietf-secsh-filexfer-02 (SFTP v3)
5. OpenSSH behavior as extracted in `EXISTING_SSH_STRUCTURE.md`

## 2. Product Thesis

FrankenSSH V1 is a clean-room Rust SSH implementation with two core
innovations:

1. Hybrid post-quantum key exchange (ML-KEM-768 + X25519) as an additive
   security mode, never weaker than classical X25519.
2. Type-state protocol enforcement where invalid protocol sequencing is
   unrepresentable at compile time for public engine APIs.

## 3. V1 Scope Contract

V1 scope includes:

1. SSH transport: version exchange, KEX, encrypted packet flow, rekey
2. Authentication: publickey, password, keyboard-interactive, certificates
3. Channels: session, direct-tcpip, forwarded-tcpip, auth-agent
4. Session operations: PTY, shell, exec, env, signals, exit status
5. SFTP v3 core operations (required), with SFTP v6 as optional/non-parity-gating
   extension scope
6. SSH agent protocol basics
7. Server and client binaries
8. Differential conformance harness against real OpenSSH

Out of scope for V1 unless explicitly added to this document:

1. SSH-1
2. X11 forwarding
3. Legacy weak ciphers and DSA keys
4. GSSAPI/Kerberos
5. OpenSSH UX extras (ProxyJump, ControlMaster) beyond core protocol behavior
6. SFTP v6 parity-gating requirements unless explicitly added to
   `FEATURE_PARITY.md`

## 4. Architecture Blueprint

The canonical crate set is fixed at 15 crates:

1. `fsh-types`
2. `fsh-error`
3. `fsh-wire`
4. `fsh-crypto`
5. `fsh-transport`
6. `fsh-auth`
7. `fsh-channel`
8. `fsh-session`
9. `fsh-sftp`
10. `fsh-forward`
11. `fsh-agent`
12. `fsh-server`
13. `fsh-client`
14. `fsh-harness`
15. `frankenssh`

Layering constraints:

1. `fsh-wire` MUST be pure parse/serialize logic (no network I/O).
2. `fsh-crypto` MUST expose cryptographic operations via traits and MUST NOT
   leak key material to higher layers.
3. `fsh-transport` MUST own protocol-state transitions.
4. Domain crates (`fsh-session`, `fsh-sftp`, `fsh-forward`, `fsh-agent`) MUST
   consume channel abstractions, not raw transport internals.
5. `fsh-harness` MUST validate public behavior via `frankenssh`, not private
   crate internals.

## 5. Compatibility Model (Strict vs Hardened)

FrankenSSH defines two policy modes sharing one protocol engine.

### 5.1 Strict Mode

Strict mode MUST maximize OpenSSH-observable behavior compatibility:

1. Unknown extensions MAY be ignored when OpenSSH-compatible behavior requires.
2. Negotiation order SHOULD mirror OpenSSH preferences for scoped algorithms.
3. Rekey cadence SHOULD match OpenSSH default semantics (`RekeyLimit default
   none`): data-volume rekeying is cipher-dependent (typically between 1 GiB and
   4 GiB), and time-based rekeying is disabled by default.
4. Host key algorithm availability SHOULD align with deployed OpenSSH behavior.

### 5.2 Hardened Mode

Hardened mode MUST prioritize security with bounded compatibility tradeoffs:

1. Unknown or unsupported extensions MUST trigger fail-closed disconnect.
2. Rekey policy MUST be aggressive (target: 1 GiB or 1 hour).
3. Algorithm set MUST be modern-only and MAY enforce PQ hybrid KEX policy.
4. Defensive parser limits MUST be stricter than strict mode defaults.
5. Host-key/auth policy MUST be Ed25519 + certificate flows only.

### 5.3 Mode Invariants

Both modes MUST preserve:

1. Core SSH state machine legality
2. Disconnect reason code correctness
3. Secret handling, zeroization, and no-secret-logging guarantees

## 6. Security Model

### 6.1 Trust Boundaries

1. Untrusted boundary: bytes from peer socket
2. Parsing boundary: `fsh-wire`
3. Cryptographic boundary: `fsh-crypto`
4. State transition boundary: `fsh-transport` and type-state APIs
5. Durable trust boundary: known_hosts/host-key/session-token stores

### 6.2 Threat Priorities

1. MITM and key substitution
2. Downgrade during algorithm negotiation
3. Parser exploitation via malformed packets and length abuse
4. Side channels in secret-dependent paths
5. State confusion across protocol phases

### 6.3 Non-Negotiable Security Rules

1. Secrets MUST NOT be logged in plaintext.
2. Secret buffers MUST be zeroized on drop.
3. Randomness MUST come from OS entropy.
4. Unknown/unsupported critical algorithms MUST fail closed.
5. Certificate validation failures MUST be hard errors.

## 7. Alien-Artifact Decision Layer

For any material protocol decision, implementation and review artifacts MUST
include:

1. Explicit decision record with alternatives considered
2. Confidence and risk statement
3. Evidence references (RFC vectors, OpenSSH traces, conformance output)
4. Rollback criteria if the decision underperforms or breaks compatibility

If a heuristic is selected over a formal proof, the rejected formal approach
and reason MUST be documented.

## 8. Extreme Optimization Contract

Optimization work MUST follow a one-lever loop:

1. Baseline
2. Profile
3. Change one lever
4. Re-run conformance (behavior isomorphic outcome)
5. Re-baseline and publish delta

No optimization is valid if behavior drifts from conformance or invariants.

## 9. Correctness and Conformance Contract

A feature is parity-green only if all are true:

1. Differential conformance vs OpenSSH passes for that feature family
2. Adversarial tests and edge cases pass
3. Required invariants pass
4. `FEATURE_PARITY.md` is updated in the same patch

## 10. Protocol State Machine Contract

Canonical high-level sequence:

1. TCP connected
2. Version exchanged
3. KEXINIT exchanged
4. KEX completed
5. NEWKEYS applied
6. Service request and accept (`ssh-userauth`)
7. Authentication success
8. Channel operations
9. Graceful close or disconnect

Illegal transitions MUST be unrepresentable in type-state APIs.

### 10.1 Transition Requirements

| From | Event | To | Required behavior |
|---|---|---|---|
| `Connected` | peer version received and validated | `VersionExchanged` | validate format, enforce limits |
| `VersionExchanged` | KEXINIT exchange | `KexInitExchanged` | deterministic algorithm selection path |
| `KexInitExchanged` | algorithms selected and KEX entered | `KexRunning` | enforce negotiation and policy filters |
| `KexRunning` | KEX success + NEWKEYS (both directions) | `Encrypted` | apply keys atomically |
| `Encrypted` | `SSH_MSG_SERVICE_REQUEST` + `SSH_MSG_SERVICE_ACCEPT` for `ssh-userauth` | `Authenticating` | enforce RFC 4253 §10 service gate |
| `Authenticating` | `SSH_MSG_USERAUTH_SUCCESS` | `Authenticated` | unlock channel APIs |
| `Authenticated` | first channel open/confirm | `Ready` | enforce window and id invariants |
| `Ready` | disconnect path initiated | `Closing` | preserve ordering and reason-code contract |
| `Closing` | transport teardown | `Disconnected` | terminal state |
| any post-`Encrypted` state | rekey trigger | same logical state after rekey | preserve channel and sequencing invariants |

## 11. Wire and Transport Contract

### 11.1 Phase 2 Baseline (Normative Entry Gate)

Phase 2 implementation work is in-spec only if the baseline contracts in
Sections 11.2-11.4 are satisfied together.

### 11.2 `fsh-types` Contract

1. `fsh-types` MUST define foundational protocol newtypes:
   `SessionId`, `ChannelId`, `SeqNum`, `WindowSize`, `MessageType`,
   and `DisconnectReason`.
2. `fsh-types` MUST provide binary helpers for SSH network-byte-order parsing
   and serialization: `read_u32`, `read_bool`, `read_string`,
   `read_name_list`, `read_mpint`, `write_u32`, `write_bool`,
   `write_string`, `write_mpint`, and `write_name_list`.
3. Parsing helpers MUST be panic-free on malformed/truncated input and MUST
   return structured parse errors.
4. Helpers that consume untrusted lengths MUST perform checked bounds validation
   before allocation.
5. SFTP-specific status typing MUST NOT be a Phase 2 `fsh-types` dependency and
   MUST be introduced with `fsh-sftp` scope.
6. Crypto key-family enums are not required for Phase 2 wire parsing; algorithm
   name-lists MUST be handled as opaque strings at this phase.

### 11.3 `fsh-error` Contract

1. `fsh-error` MUST define `FshError`, `ParseError`, and a workspace-standard
   `Result<T>` alias.
2. Externally observable error paths MUST map deterministically to SSH
   disconnect reason codes (RFC 4253 §11.1).
3. A single documented fallback mapping for otherwise-unclassified internal
   errors MUST exist and remain stable unless this spec is updated.
4. Strict-mode disconnect payloads MUST use OpenSSH-compatible language-tag
   behavior (empty string unless an explicit compatibility exception is
   approved in this specification).

### 11.4 `fsh-wire` Contract

1. `fsh-wire` MUST remain pure parse/serialize logic (no network I/O).
2. Parse/serialize MUST be bounded and panic-free on malformed input.
3. Hot-path operations SHOULD avoid avoidable allocations.
4. Length fields MUST be validated before allocation.
5. Message type dispatch MUST reject unsupported critical message classes with
   mapped disconnect reasons.
6. The Phase 2 message baseline MUST include wire structs implementing
   parse/serialize/message-type behavior for:
   `KexInit`, `KexDhInit`, `KexDhReply`, `NewKeys`, `ExtInfo`, `ServiceRequest`,
   `ServiceAccept`, `UserAuthRequest`, `UserAuthSuccess`, `UserAuthFailure`,
   `UserAuthBanner`, `ChannelOpen`, `ChannelOpenConfirmation`,
   `ChannelOpenFailure`, `ChannelData`, `ChannelExtendedData`,
   `ChannelWindowAdjust`, `ChannelEof`, `ChannelClose`, `ChannelRequest`,
   `ChannelSuccess`, `ChannelFailure`, `GlobalRequest`, `RequestSuccess`,
   `RequestFailure`, `Disconnect`, `Ignore`, `Unimplemented`, and `Debug`.
7. Message types in KEX method-specific range (30-49) and auth method-specific
   range (60-79) are context-dependent. Phase 2 wire structs in these ranges
   MUST keep method-specific payload bytes opaque.
8. `KexDhInit` and `KexDhReply` are Phase 2 wire-layer names for message types
   30 and 31. Their method-specific interpretation is deferred to higher-layer
   crates in Phases 3-5.

Transport requirements:

1. Sequence numbers MUST be monotonic modulo SSH limits.
2. Rekey triggers MUST be configurable by byte and time thresholds.
3. Strict KEX behavior MUST match scoped OpenSSH expectations in strict mode,
   including OpenSSH pseudo-algorithm negotiation (`kex-strict-c-v00@openssh.com`,
   `kex-strict-s-v00@openssh.com`) and MUST NOT conflate strict-KEX with RFC 8308
   ext-info negotiation.

## 12. Algorithm and Negotiation Contract

Required KEX baseline:

1. `curve25519-sha256`
2. `ecdh-sha2-nistp256`
3. `sntrup761x25519-sha512`
4. `diffie-hellman-group16-sha512`
5. `diffie-hellman-group18-sha512`

Required cipher baseline:

1. `chacha20-poly1305@openssh.com`
2. `aes256-gcm@openssh.com`
3. `aes256-ctr` + `hmac-sha2-256`

Required host-key baseline:

1. `ssh-ed25519`
2. `rsa-sha2-256/512`
3. `ecdsa-sha2-nistp256`

PQ hybrid policy:

1. Hybrid ML-KEM-768 + X25519 is a required design target.
2. Workspace dependency selection for `ml-kem` is currently deferred.
3. Until enabled, classical KEX MUST remain interoperable with OpenSSH.

Negotiation rules:

1. Unknown algorithms MUST NOT silently downgrade to weaker unexpected options.
2. Mode policy MUST control accepted algorithm sets deterministically.
3. Effective negotiated suite MUST be auditable (without exposing secrets).

## 13. Authentication Contract

Supported methods:

1. `publickey`
2. `password`
3. `keyboard-interactive`
4. certificate-based variants for scoped key types

Requirements:

1. Partial success semantics MUST match RFC/OpenSSH behavior.
2. Attempt limiting MUST be enforced.
3. Auth banners MUST preserve compatibility expectations in strict mode.
4. Password and signature checks MUST be constant-time where secret-dependent.

## 14. Channel and Subsystem Contract

Channel rules:

1. Channel IDs MUST be unique per connection direction.
2. Window adjustments MUST preserve flow-control invariants.
3. Close sequencing MUST prevent double-close inconsistencies.

Session rules:

1. PTY, exec, env, signal, and exit-status flow MUST match scoped OpenSSH
   sequencing.

SFTP rules:

1. V3 init/version negotiation is REQUIRED.
2. Request/response correlation MUST be exact.
3. Core file ops in `FEATURE_PARITY.md` are REQUIRED for V1 parity.
4. SFTP v6 MAY be implemented as optional extension scope, but is non-parity-
   gating unless explicitly tracked in `FEATURE_PARITY.md`.

Forwarding rules:

1. local, remote, and dynamic forwarding channel types are in scope.

Agent rules:

1. identity listing and sign-request flows are REQUIRED.

## 15. Error and Disconnect Contract

`FshError` MUST map to SSH disconnect reason codes for externally observable
errors. Unknown internal error classes MUST map to a deterministic default
disconnect code with structured internal diagnostics.

### 15.1 Minimum Required Mapping Baseline (Phase 2)

At minimum, the following mappings are REQUIRED:

| `FshError` class | SSH disconnect reason |
|---|---|
| `Protocol` | `SSH_DISCONNECT_PROTOCOL_ERROR` (2) |
| `KexFailed` | `SSH_DISCONNECT_KEY_EXCHANGE_FAILED` (3) |
| `UnsupportedAlgorithm` | `SSH_DISCONNECT_KEY_EXCHANGE_FAILED` (3) |
| `Crypto` | `SSH_DISCONNECT_MAC_ERROR` (5) |
| `ServiceNotAvailable` (or equivalent service-gate failure class) | `SSH_DISCONNECT_SERVICE_NOT_AVAILABLE` (7) |
| `VersionMismatch` | `SSH_DISCONNECT_PROTOCOL_VERSION_NOT_SUPPORTED` (8) |
| `HostKeyVerification` | `SSH_DISCONNECT_HOST_KEY_NOT_VERIFIABLE` (9) |
| `ConnectionLost` | `SSH_DISCONNECT_CONNECTION_LOST` (10) |
| `Timeout` | `SSH_DISCONNECT_BY_APPLICATION` (11) |
| `Cancelled` | `SSH_DISCONNECT_BY_APPLICATION` (11) |
| `TooManyConnections` | `SSH_DISCONNECT_TOO_MANY_CONNECTIONS` (12) |
| `AuthCancelled` | `SSH_DISCONNECT_AUTH_CANCELLED_BY_USER` (13) |
| `AuthFailed` | `SSH_DISCONNECT_NO_MORE_AUTH_METHODS_AVAILABLE` (14) |

Additional variants MAY exist, but MUST still map deterministically and be
covered by tests.

Disconnect behavior MUST specify:

1. code
2. human-readable reason string (without secrets)
3. language tag behavior (strict mode MUST use empty string for OpenSSH
   compatibility unless an explicit compatibility exception is documented)
4. sequence timing relative to channel/transport shutdown

## 16. RaptorQ-Everywhere Durability Contract

RaptorQ applies to durable artifacts, not ephemeral transport memory.

Durable artifact classes:

1. `known_hosts` and host-key trust databases
2. persistent session resumption token stores
3. serialized configurations
4. conformance artifacts and benchmark evidence bundles
5. migration/reproducibility ledgers tied to compatibility decisions

Required outputs per artifact class:

1. repair-symbol generation manifest
2. integrity scrub report
3. decode proof artifact for each recovery event

Ephemeral exclusions:

1. in-flight session keys
2. packet buffers
3. channel transient runtime state

These remain governed by forward secrecy, memory safety, and zeroization.

### 16.1 Artifact Envelope Requirements

Each durable artifact class MUST define:

1. primary artifact schema/version
2. sidecar schema/version
3. scrub cadence
4. decode proof retention policy
5. tamper-evident checksum/hash strategy

## 17. Conformance Harness Specification

Harness source of truth:

1. real OpenSSH binaries and behavior traces
2. fixture vectors for handshake/auth/channel/error paths

Harness MUST cover:

1. successful handshakes for each supported suite combination
2. expected auth success and failure paths
3. channel lifecycle correctness
4. disconnect code correctness under protocol error scenarios
5. regression goldens for packet-level sequencing where feasible
6. deterministic replay package in Phase 8, containing at minimum:
   - `session-trace.jsonl` (timestamped state/message trace with mode/config)
   - `oracle-diff.md` (behavior delta report against OpenSSH oracle runs)
   - provenance block (`git_sha`, `toolchain`, `command`, `utc_timestamp`)

OpenSSH oracle path (local gitignored dependency):

1. `legacy_openssh_code/openssh-portable`
2. Harness preflight MUST fail if this path is missing.

## 18. Performance Budgets and SLO Targets

Initial SLO targets (subject to calibration once implementation lands):

1. Handshake latency p95 <= 1.25x OpenSSH baseline on same host/profile
2. Throughput >= 0.90x OpenSSH baseline for bulk transfer scenarios
3. Channel processing overhead p95 <= 1.50x OpenSSH baseline

Every optimization change MUST publish before/after deltas with workload and
environment identifiers.

### 18.1 Runtime Resource Limits (Phase 4 Normative Baseline)

To bound parser/transport resource exposure, Phase 4 transport implementation
MUST enforce concrete defaults (configurable, but never unbounded):

1. `max_packet_bytes`: `262144` (256 KiB) hard cap per inbound packet.
2. `max_channels_per_connection`: `64`.
3. `max_inbound_buffer_bytes_per_connection`: `8388608` (8 MiB).
4. `max_outbound_buffer_bytes_per_connection`: `8388608` (8 MiB).
5. `max_in_flight_global_requests`: `32`.

Backpressure behavior MUST be deterministic:

1. when inbound/outbound buffer caps are reached, transport MUST stop accepting
   new application payload until pressure recovers below a documented watermark;
2. if pressure cannot recover within a bounded timeout, connection handling MUST
   fail closed with a mapped disconnect reason.

## 19. CI Gate Topology (Release-Critical)

Core required gate commands:

```bash
cargo fmt --check
cargo check --all-targets
cargo clippy --all-targets -- -D warnings
cargo test --workspace
```

Additional required gates for conformance/performance scope:

```bash
cargo test -p fsh-harness -- --nocapture
cargo bench -p fsh-harness
```

Advisory security gate (non-blocking unless policy escalates):

```bash
cargo audit
```

The CI workflow definitions under `.github/workflows` are part of the normative
release gate topology and MUST stay aligned with this section (core,
scope-triggered, advisory).

## 20. Milestones and Exit Criteria

### M0 - Spec Foundation

Exit criteria:

1. this spec committed
2. doc cross-links consistent
3. drift audit checklist executable

### M1 - Types/Wire Baseline (Phase 2)

Exit criteria:

1. Sections 11.2-11.4 Phase 2 baseline implemented with evidence
   (round-trip/property/fuzz/OpenSSH fixture parsing)

### M2 - Crypto Primitive Baseline (Phase 3)

Exit criteria:

1. baseline cipher/KEX/host-key primitives integrated
2. RFC vector evidence published

### M3 - First End-to-End SSH Session

Exit criteria:

1. handshake + auth + session channel succeed against OpenSSH in strict mode
2. disconnect/error mapping validated for key negative cases

### M4 - Subsystem Expansion

Exit criteria:

1. SFTP core operations pass conformance matrix
2. forwarding and agent minimum scopes pass harness

### M5 - Hardening and Performance

Exit criteria:

1. hardened mode policy compliance validated
2. performance and side-channel evidence updated
3. parity and risk registers updated

## 21. Risk Register (Normative Tracking)

| Risk | Severity | Mitigation |
|---|---|---|
| Protocol divergence from OpenSSH edge behavior | High | strict-mode conformance-first development and golden trace diffs |
| PQ algorithm ecosystem churn | High | feature-gated hybrid integration and explicit fallback policy |
| Parser resource exhaustion | High | bounded reads/allocations and fuzz/property testing |
| State confusion during rekey and channel overlap | High | type-state transitions + deterministic concurrency tests |
| Documentation drift | Medium | mandatory same-patch updates + mechanical drift checklist |

## 22. Feature Parity Contract

`FEATURE_PARITY.md` is a release-critical ledger.

Rules:

1. No feature may move to parity-green without evidence links.
2. Any behavior change MUST update the relevant parity rows in the same patch.
3. Coverage percentage claims MUST be derived from matrix counts, never ad hoc.

Current project snapshot indicates 0/58 feature coverage at bootstrap and is
acceptable only while M0/M1 execution is in progress.

## 23. Implementation Snapshot (2026-02-14)

Status as of February 14, 2026:

1. 15-crate workspace scaffold exists.
2. Canonical specification set now includes this comprehensive spec.
3. OpenSSH oracle checkout path is documented and locally provisionable.
4. `asupersync` integration is planned/deferred in current Cargo snapshot.
5. `ml-kem` crate selection is planned/deferred in current Cargo snapshot.
6. CI workflows under `.github/workflows` are authored for core/scope-triggered/advisory gates.
7. Implementation remains at bootstrap documentation stage.

## 24. Immediate Execution Checklist

1. Keep `.github/workflows` aligned with the normative gate topology in Section 19.
2. Finish transport/auth/channel transition tables in
   `EXISTING_SSH_STRUCTURE.md`.
3. Implement Phase 2 `fsh-types`/`fsh-error`/`fsh-wire` minimum slice.
4. Land first conformance harness smoke test against local OpenSSH oracle.
5. Update `FEATURE_PARITY.md` only with evidence-backed status changes.
6. Record any approved behavior divergence in `COMPATIBILITY_EXCEPTIONS.md`.

## 25. Change Control

Any patch that changes protocol behavior, compatibility policy, or durable
artifact handling MUST update this document in the same patch.

If implementation and spec diverge, implementation is considered out-of-spec
until either:

1. implementation is corrected, or
2. this document is updated with explicit rationale and acceptance evidence,
   AND the approved deviation is recorded in `COMPATIBILITY_EXCEPTIONS.md`
   with scope, rationale, and evidence links.

## 26. Phase 2 API Contract Appendix (Normative)

This appendix defines the minimum public contract shape for Phase 2
implementation work (`fsh-types`, `fsh-error`, `fsh-wire`).

### 26.1 `fsh-types` Minimum API and Invariants

Required type wrappers (shape-level contract):

```rust
pub struct SessionId(pub u64);
pub struct ChannelId(pub u32);
pub struct SeqNum(pub u32);
pub struct WindowSize(pub u32);
pub struct MessageType(pub u8);
pub struct DisconnectReason(pub u32);
```

Required helper API family (signature-level contract; concrete containers MAY be
zero-copy wrappers):

```rust
pub fn read_u32(input: &mut &[u8]) -> Result<u32, ParseError>;
pub fn read_bool(input: &mut &[u8]) -> Result<bool, ParseError>;
pub fn read_string(input: &mut &[u8]) -> Result<&[u8], ParseError>;
pub fn read_name_list(input: &mut &[u8]) -> Result<Vec<&[u8]>, ParseError>;
pub fn read_mpint(input: &mut &[u8]) -> Result<Vec<u8>, ParseError>;
pub fn write_u32(out: &mut Vec<u8>, value: u32);
pub fn write_bool(out: &mut Vec<u8>, value: bool);
pub fn write_string(out: &mut Vec<u8>, value: &[u8]);
pub fn write_name_list(out: &mut Vec<u8>, names: &[&[u8]]);
pub fn write_mpint(out: &mut Vec<u8>, value: &[u8]);
```

Failure semantics:

1. Helpers MUST NOT panic on malformed/truncated input.
2. Length-driven helpers MUST bound-check before allocation/advance.
3. Name-list parsing MUST reject invalid separator/token encoding deterministically.
4. Failure behavior MUST be deterministic and map to structured `ParseError`
   classes suitable for disconnect mapping in higher layers.
5. `read_bool` MUST normalize any non-zero byte to `true`; `write_bool` MUST
   emit only `0x00` or `0x01`.

### 26.2 `fsh-error` Minimum API and Failure Semantics

Required classes:

1. `FshError` (cross-layer operational/protocol error envelope)
2. `ParseError` (wire/helper parsing failures)
3. `Result<T>` alias bound to the project error envelope

Required behavior:

1. Externally observable error classes MUST map deterministically to SSH
   disconnect reason codes per Section 15.1.
2. A stable fallback mapping MUST exist for unclassified internal failures.
3. Public-facing reason strings MUST be secret-safe and strict-mode language tag
   behavior MUST remain OpenSSH-compatible.

### 26.3 `fsh-wire` Minimum API and Failure Semantics

Required trait shape:

```rust
pub trait WirePacket: Sized {
    const MESSAGE_TYPE: u8;
    fn parse(payload: &[u8]) -> Result<Self, ParseError>;
    fn serialize(&self, out: &mut Vec<u8>) -> Result<(), ParseError>;
}
```

Required dispatch behavior:

1. Message dispatch MUST route by SSH message type number to the Phase 2
   baseline message set defined in Section 11.4.
2. `SSH_MSG_EXT_INFO` (type 7) MUST be parseable at wire layer. Phase 2 keeps
   extension key/value payloads opaque.
3. Context-dependent ranges (30-49 and 60-79) MUST preserve method-specific
   payload bytes without semantic interpretation.
4. Unsupported critical message classes MUST fail closed with deterministic
   mapped disconnect behavior.
5. Parse and serialize behavior MUST remain bounded and panic-free.
6. Wire APIs MUST remain pure and MUST NOT perform network I/O.
