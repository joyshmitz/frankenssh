# PLAN_TO_PORT_SSH_TO_RUST.md

> **FrankenSSH** — A memory-safe, clean-room Rust reimplementation of SSH-2
> with post-quantum hybrid key exchange and compile-time protocol safety.
>
> This document is the **canonical porting plan** following the four-document
> methodology. It defines scope, exclusions, phased delivery, risks, and
> success criteria.
>
> Companion documents:
> - `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md` — canonical normative spec (supersedes on conflicts)
> - `PROPOSED_ARCHITECTURE.md` — crate topology, dependency DAG, trait contracts
> - `AGENTS.md` — guardrails for agent changes in this repo
> - `EXISTING_SSH_STRUCTURE.md` — behavior extraction from OpenSSH
> - `FEATURE_PARITY.md` — parity status tracking
> - `FRANKENSSH_PROPOSAL.md` — comprehensive top-level proposal

---

## 0. Execution TODO (Canonical)

Status legend: `[ ]` not started, `[~]` in progress, `[x]` complete.

### 0.1 Documentation and Consistency (Blocker Before Deep Implementation)

- [x] Canonicalize public facade crate naming across docs (`frankenssh`; no phantom `fsh` facade crate)
- [x] Reconcile dependency claims vs workspace reality (`asupersync` currently deferred/commented in `Cargo.toml`; `ml-kem` planned but not yet selected in workspace dependencies)
- [x] Add explicit legacy-oracle bootstrap note for `legacy_openssh_code/openssh-portable` and clarify that the checkout is local/gitignored
- [x] Remove/repair stale claims that companion docs "will be created later" when they already exist
- [x] Author `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md` and mark it as canonical where conflicts exist
- [x] CI workflows under `.github/workflows` authored for core/scope-triggered/advisory gates

### 0.1.1 Drift Audit Checklist (Mechanical)

Run from repo root whenever doc drift is suspected:

```bash
# Workspace membership sanity.
cargo metadata --no-deps --format-version 1 | jq '.workspace_members | length'
# Crates directory count (expect 14 here; the 15th crate `frankenssh` is at workspace root).
# Use `find` to avoid shell aliases (e.g., `ls` -> `eza`) skewing the count.
find crates -mindepth 1 -maxdepth 1 -type d | wc -l

# Facade crate naming drift (`frankenssh` vs phantom `fsh` facade).
rg -n '`fsh`|phantom `fsh` facade|public facade' -S *.md

# Dependency drift against Cargo.toml snapshot.
rg -n 'ml-kem|asupersync|anyhow' -S *.md
rg -n 'asupersync|ml-kem|anyhow' -S Cargo.toml crates/*/Cargo.toml

# Legacy oracle path/bootstrap drift.
rg -n 'legacy_openssh_code/openssh-portable|git clone https://github.com/openssh/openssh-portable' -S *.md
test -d legacy_openssh_code/openssh-portable || echo "missing local OpenSSH oracle checkout (run bootstrap clone command)"

# Workflow presence drift.
ls -1 .github/workflows/*.yml
```

### 0.2 Bootstrap

- [x] Initialize git repo, workspace Cargo.toml, rust-toolchain.toml
- [x] Create all 15 crate stubs with correct inter-crate dependencies
- [x] Write AGENTS.md, README.md, porting docs

### 0.3 Types & Wire (Phase 2)

- [ ] `fsh-types`: newtypes (SessionId, ChannelId, SeqNum, MessageType, WindowSize)
- [ ] `fsh-types`: binary helpers (read_u32, read_string, read_mpint, write_*)
- [ ] `fsh-error`: FshError enum (17 variants), disconnect reason mapping
- [ ] `fsh-wire`: all SSH message structs with WirePacket trait
- [ ] Round-trip tests for every message type
- [ ] Fuzz target for packet parsing

### 0.3.1 Phase 2 Acceptance Gate (Normative)

Phase 2 MAY be marked complete only when all criteria below are met.

1. `fsh-types`:
   - Foundational newtypes are defined: `SessionId`, `ChannelId`, `SeqNum`,
     `WindowSize`, `MessageType`, `DisconnectReason`, `SftpStatus`, `KeyType`.
   - Binary helpers exist and are used as the default parse path for wire code:
     `read_u32`, `read_string`, `read_mpint`, `write_u32`, `write_string`,
     `write_mpint`, `write_name_list`.
   - Helpers are panic-free on malformed input and enforce checked bounds before
     any allocation.
2. `fsh-error`:
   - `FshError` and `ParseError` taxonomies are defined with structured variants
     suitable for transport/auth/channel/wire boundaries.
   - Externally observable failures map deterministically to SSH disconnect
     reason codes (RFC 4253 §11.1), with one documented stable fallback mapping
     for otherwise-unclassified internal errors.
   - Disconnect reason text and language-tag behavior are OpenSSH-compatible in
     strict mode and MUST NOT leak secrets.
3. `fsh-wire`:
   - `WirePacket` parse/serialize/message-type behavior exists for the complete
     Phase 2 message baseline defined in
     `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md` Section 11.4.
   - Parsing remains pure (no network I/O) and bounded by explicit size checks.
   - Unsupported critical message classes fail closed with deterministic mapped
     disconnect behavior.
4. Evidence and tests:
   - Byte-for-byte round-trip tests for each Phase 2 message struct.
   - Property tests (`proptest`) for valid message generation/round-trip.
   - Parser fuzz target with no panics on arbitrary inputs.
   - Successful parse of at least one captured OpenSSH handshake trace.

### 0.3.2 Phase 2 Exit Evidence Package

The Phase 2 completion PR MUST include or link all of:

1. `fsh-types` invariants checklist (newtype bounds + helper behavior).
2. `fsh-error` disconnect mapping table with RFC reason-code references.
3. `fsh-wire` message coverage table for the Phase 2 baseline.
4. Test evidence for round-trip, property tests, fuzzing, and OpenSSH fixture
   parsing.

### 0.4 Crypto (Phase 3)

- [ ] CipherSuite trait + chacha20-poly1305 implementation
- [ ] CipherSuite: aes256-gcm, aes256-ctr+hmac
- [ ] KexAlgorithm: curve25519-sha256
- [ ] KexAlgorithm: mlkem768x25519-sha256 (hybrid PQ)
- [ ] Key derivation (RFC 4253 §7.2)
- [ ] Host key types: Ed25519, RSA-SHA2, ECDSA
- [ ] RFC test vectors for all algorithms

### 0.5 Transport (Phase 4)

- [ ] Version exchange
- [ ] Algorithm negotiation (KexInit)
- [ ] Key exchange orchestration
- [ ] Type-state Session<S> machine
- [ ] Encrypted packet I/O
- [ ] Rekey support
- [ ] Strict KEX extension

### 0.6 Auth & Channels (Phase 5)

- [ ] Pubkey authentication (two-phase)
- [ ] Password authentication
- [ ] Keyboard-interactive authentication
- [ ] Certificate authentication
- [ ] Channel multiplexing and flow control
- [ ] Window management

### 0.7 Session & Subsystems (Phase 6)

- [ ] PTY allocation, exec, shell, env, signals
- [ ] SFTP v3 protocol
- [ ] Local/remote/dynamic port forwarding
- [ ] SSH agent protocol

### 0.8 Server & Client (Phase 7)

- [ ] fsh-server: TCP listener, host key loading, auth dispatch
- [ ] fsh-client: connection, config parsing, known_hosts
- [ ] Self-interop (fsh-client ↔ fsh-server)

### 0.9 Harness & API (Phase 8)

- [ ] Conformance harness vs real OpenSSH
- [ ] Public API facade (frankenssh crate)
- [ ] Documentation and examples

---

## 1. Scope

See `FRANKENSSH_PROPOSAL.md` Part IV for full scope definition.

## 2. Explicit Exclusions

| Exclusion | Rationale |
|-----------|-----------|
| SSH-1 protocol | Cryptographically broken |
| X11 forwarding | Archaic, massive attack surface |
| GSSAPI/Kerberos | Enterprise-specific plugin |
| Legacy ciphers (3DES, Blowfish, RC4) | Cryptographically weak |
| DSA keys | NIST deprecated |
| Host-based auth | Insecure trust model |
| Compression (zlib) | CRIME/BREACH attack surface |
| ssh-keygen/ssh-copy-id | Utility scripts, not core protocol |

## 3. Eight Phases

See `FRANKENSSH_PROPOSAL.md` Part V for detailed phase descriptions with
acceptance criteria, LOC estimates, risks, and duration.

## 4. Success Criteria

See `FRANKENSSH_PROPOSAL.md` Part VIII for testing strategy, conformance
harness design, and performance targets.

## 5. RaptorQ Durability Status (Current)

Current status: contract specified; implementation deferred until durable SSH
artifact stores land.

Durable artifact scope for FrankenSSH:

1. `known_hosts` and host-key trust databases
2. Persistent session resumption token stores
3. Serialized configurations
4. Conformance/benchmark evidence artifacts
5. Migration/reproducibility ledgers tied to compatibility decisions

Required artifact envelope (when implemented):

1. Repair-symbol generation manifest
2. Integrity scrub report
3. Decode proof artifact for each recovery event

Near-term next step:

1. Add sidecar generation for the first conformance/benchmark artifact pair.
