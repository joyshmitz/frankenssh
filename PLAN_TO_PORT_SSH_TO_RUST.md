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

# Compatibility exception ledger presence.
test -f COMPATIBILITY_EXCEPTIONS.md || echo "missing COMPATIBILITY_EXCEPTIONS.md"

# Beads health checks (safe before bootstrap).
test -d .beads && br doctor --json || echo "beads workspace not initialized"
test -d .beads && br dep cycles --json || true
```

### 0.1.2 Beads Planning Substrate (Blocker Before Deep Implementation)

Execution quality depends on backlog quality. Before substantial coding, the
Beads graph MUST be initialized and reviewable.

- [ ] Initialize Beads with explicit project prefix (`br init --prefix fsh`)
- [ ] Seed only the near-term execution kernel (no bulk backlog dump): target 10-16 issues, 3-4 epics, dependency depth <= 3
- [ ] Keep seed graph acyclic (`br dep cycles --json` returns empty cycle set)
- [ ] Require each implementation bead to include:
  - unit-test commands and expected outcomes
  - e2e script path(s) and command lines
  - structured logging contract (`trace_id`, `mode`, `phase`, `crate`, `scenario`, `outcome`, `latency_ns`, `artifact_refs`)
  - evidence artifact location(s) (repo path and/or CI artifact URL)
- [ ] Map every seed bead to at least one `PLAN` phase item and one `FEATURE_PARITY` row
- [ ] Use `br` as the only mutation interface for issue state/dependencies (no manual JSONL edits)

### 0.2 Bootstrap

- [x] Initialize git repo, workspace Cargo.toml, rust-toolchain.toml
- [x] Create all 15 crate stubs with correct inter-crate dependencies
- [x] Write AGENTS.md, README.md, porting docs

### 0.3 Types & Wire (Phase 2)

- [ ] `fsh-types`: newtypes (SessionId, ChannelId, SeqNum, MessageType, WindowSize, DisconnectReason)
- [ ] `fsh-types`: binary helpers (read_u32, read_bool, read_string, read_name_list, read_mpint, write_*)
- [ ] `fsh-error`: `FshError` + `ParseError` taxonomy, disconnect reason mapping
- [ ] `fsh-wire`: all SSH message structs with WirePacket trait
- [ ] `fsh-wire`: types 30-49 and 60-79 follow opaque payload strategy (context-dependent semantics deferred)
- [ ] Round-trip tests for every message type
- [ ] Property tests (`proptest`) for parser/serializer round-trip invariants
- [ ] Fuzz target for packet parsing
- [ ] Parse at least one captured OpenSSH handshake fixture without parser errors

### 0.3.1 Phase 2 Acceptance Gate (Normative)

Phase 2 MAY be marked complete only when all criteria below are met.

1. `fsh-types`:
   - Foundational newtypes are defined: `SessionId`, `ChannelId`, `SeqNum`,
     `WindowSize`, `MessageType`, `DisconnectReason`.
   - SFTP-specific status typing is out of Phase 2 scope and MUST land with
     `fsh-sftp` work in Phase 6.
   - Crypto-specific key-family typing is out of Phase 2 scope; wire parsing
     treats algorithm names as opaque strings at this phase.
   - Binary helpers exist and are used as the default parse path for wire code:
     `read_u32`, `read_bool`, `read_string`, `read_name_list`, `read_mpint`,
     `write_u32`, `write_bool`, `write_string`, `write_mpint`,
     `write_name_list`.
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
   - Context-dependent message ranges (30-49, 60-79) preserve opaque
     method-specific payload bytes in Phase 2.
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
5. Deterministic replay artifacts are Phase 8 scope and MUST NOT be used as a
   Phase 2 completion requirement.
6. Bead-closure evidence index mapping each closed Phase 2 bead to:
   - unit-test command/output reference
   - e2e script command/output reference
   - structured log artifact reference

### 0.3.3 Phase 2 Evidence Artifact Format (Review-Ready)

Phase 2 evidence MUST be submitted in a deterministic review format.

1. Artifact root:
   - logical path schema: `artifacts/phase2/<YYYY-MM-DD>/<short-sha>/`
   - note: `.gitignore` excludes `artifacts/` by default; this path is a
     canonical layout identifier, not a requirement that files be git-tracked.
2. Required files:
   - `types-invariants.md` (`fsh-types` newtypes/helpers + invariant checks)
   - `error-mapping.md` (`FshError`/`ParseError` mapping to disconnect reasons)
   - `wire-coverage.md` (Phase 2 message baseline coverage table)
   - `bead-evidence-index.md` (closed-bead -> tests/e2e/log evidence mapping)
   - `roundtrip-summary.txt` (message-by-message byte equality summary)
   - `proptest-summary.txt` (property test counts, failures, repro seeds)
   - `fuzz-summary.txt` (target name, runtime, crashes, corpus notes)
   - `openssh-fixture-parse.txt` (fixture source and parser outcome)
3. Each file MUST include provenance header fields:
   - `git_sha`
   - `utc_timestamp`
   - `toolchain` (`rustc -Vv` summary)
   - `command` (exact executed command line)
4. Failure reporting:
   - if a required command fails, the artifact MUST still be emitted with
     non-zero exit status and captured stderr snippet.
5. Traceability:
   - each readiness artifact MUST state the mapped
     `FEATURE_PARITY.md` row(s) and `PLAN` Section `0.3.1` item(s) it satisfies.
6. Publication modes (MUST choose at least one per completion PR):
   - CI artifact publication with stable job URL(s) pointing to files laid out
     under the canonical logical path schema.
   - External immutable artifact store URL(s) with checksum references included
     in the PR description.
   - Git-tracked snapshot under `artifacts/phase2/...` only when explicitly
     needed for audit/reproducibility; if used, include via `git add -f`.

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
- [ ] Runtime resource limits + deterministic backpressure enforcement

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
- [ ] Deterministic replay evidence package (`session-trace.jsonl`, `oracle-diff.md`, provenance metadata)
- [ ] Interop matrix reporting (mode x direction x auth-method x rekey scenario)
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
