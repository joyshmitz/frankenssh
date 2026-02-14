# PLAN_TO_PORT_SSH_TO_RUST.md

> **FrankenSSH** — A memory-safe, clean-room Rust reimplementation of SSH-2
> with post-quantum hybrid key exchange and compile-time protocol safety.
>
> This document is the **canonical porting plan** following the four-document
> methodology. It defines scope, exclusions, phased delivery, risks, and
> success criteria.
>
> Companion documents:
> - `PROPOSED_ARCHITECTURE.md` — crate topology, dependency DAG, trait contracts
> - `AGENTS.md` — guardrails for agent changes in this repo
> - `EXISTING_SSH_STRUCTURE.md` — behavior extraction from OpenSSH
> - `FEATURE_PARITY.md` — parity status tracking
> - `FRANKENSSH_PROPOSAL.md` — comprehensive top-level proposal

---

## 0. Execution TODO (Canonical)

Status legend: `[ ]` not started, `[~]` in progress, `[x]` complete.

### 0.1 Bootstrap

- [x] Initialize git repo, workspace Cargo.toml, rust-toolchain.toml
- [x] Create all 15 crate stubs with correct inter-crate dependencies
- [x] Write AGENTS.md, README.md, porting docs
- [ ] CI pipeline (fmt, check, clippy, test)

### 0.2 Types & Wire (Phase 2)

- [ ] `fsh-types`: newtypes (SessionId, ChannelId, SeqNum, MessageType, WindowSize)
- [ ] `fsh-types`: binary helpers (read_u32, read_string, read_mpint, write_*)
- [ ] `fsh-error`: FshError enum (17 variants), disconnect reason mapping
- [ ] `fsh-wire`: all SSH message structs with WirePacket trait
- [ ] Round-trip tests for every message type
- [ ] Fuzz target for packet parsing

### 0.3 Crypto (Phase 3)

- [ ] CipherSuite trait + chacha20-poly1305 implementation
- [ ] CipherSuite: aes256-gcm, aes256-ctr+hmac
- [ ] KexAlgorithm: curve25519-sha256
- [ ] KexAlgorithm: mlkem768x25519-sha256 (hybrid PQ)
- [ ] Key derivation (RFC 4253 §7.2)
- [ ] Host key types: Ed25519, RSA-SHA2, ECDSA
- [ ] RFC test vectors for all algorithms

### 0.4 Transport (Phase 4)

- [ ] Version exchange
- [ ] Algorithm negotiation (KexInit)
- [ ] Key exchange orchestration
- [ ] Type-state Session<S> machine
- [ ] Encrypted packet I/O
- [ ] Rekey support
- [ ] Strict KEX extension

### 0.5 Auth & Channels (Phase 5)

- [ ] Pubkey authentication (two-phase)
- [ ] Password authentication
- [ ] Keyboard-interactive authentication
- [ ] Certificate authentication
- [ ] Channel multiplexing and flow control
- [ ] Window management

### 0.6 Session & Subsystems (Phase 6)

- [ ] PTY allocation, exec, shell, env, signals
- [ ] SFTP v3 protocol
- [ ] Local/remote/dynamic port forwarding
- [ ] SSH agent protocol

### 0.7 Server & Client (Phase 7)

- [ ] fsh-server: TCP listener, host key loading, auth dispatch
- [ ] fsh-client: connection, config parsing, known_hosts
- [ ] Self-interop (fsh-client ↔ fsh-server)

### 0.8 Harness & API (Phase 8)

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
