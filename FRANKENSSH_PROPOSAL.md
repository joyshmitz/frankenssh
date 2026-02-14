# FRANKENSSH_PROPOSAL.md

> **FrankenSSH (fsh)** — A memory-safe, clean-room Rust reimplementation of the
> SSH-2 protocol with post-quantum hybrid key exchange and compile-time
> protocol state enforcement.
>
> This document is the top-level proposal following the four-document
> methodology proven by the FrankenFS project. It defines project identity,
> methodology, scope, architecture, phased delivery, risks, and success
> criteria.

---

## Table of Contents

- [Part I: Methodology](#part-i-methodology)
  - [1. The Four-Document Methodology](#1-the-four-document-methodology)
  - [2. Core Principles](#2-core-principles)
  - [3. Porting Doctrine](#3-porting-doctrine)
  - [4. Quality Controls](#4-quality-controls)
- [Part II: Project Identity](#part-ii-project-identity)
  - [5. What FrankenSSH Is](#5-what-frankenssh-is)
  - [6. Innovation Layer](#6-innovation-layer)
  - [7. Legacy Corpus](#7-legacy-corpus)
  - [8. RFC Corpus](#8-rfc-corpus)
- [Part III: Architecture](#part-iii-architecture)
  - [9. 15-Crate Workspace](#9-15-crate-workspace)
  - [10. Dependency Graph](#10-dependency-graph)
  - [11. Key Traits](#11-key-traits)
  - [12. Error Model](#12-error-model)
  - [13. Type-State Protocol Machine](#13-type-state-protocol-machine)
- [Part IV: Scope](#part-iv-scope)
  - [14. Deliverables](#14-deliverables)
  - [15. Explicit Exclusions](#15-explicit-exclusions)
  - [16. Target Platform](#16-target-platform)
  - [17. Key Dependencies](#17-key-dependencies)
- [Part V: Phased Delivery](#part-v-phased-delivery)
  - [18. Eight Phases](#18-eight-phases)
  - [19. Phase Dependencies](#19-phase-dependencies)
  - [20. LOC Estimates](#20-loc-estimates)
- [Part VI: Behavioral Extraction](#part-vi-behavioral-extraction)
  - [21. OpenSSH Module Map](#21-openssh-module-map)
  - [22. Binary Packet Format](#22-binary-packet-format)
  - [23. Key Exchange Behavior](#23-key-exchange-behavior)
  - [24. Authentication Behavior](#24-authentication-behavior)
  - [25. Channel Multiplexing Behavior](#25-channel-multiplexing-behavior)
  - [26. SFTP Subsystem Behavior](#26-sftp-subsystem-behavior)
  - [27. Agent Protocol Behavior](#27-agent-protocol-behavior)
- [Part VII: Feature Parity](#part-vii-feature-parity)
  - [28. Capability Matrix](#28-capability-matrix)
  - [29. Blocking Gaps](#29-blocking-gaps)
- [Part VIII: Conformance & Testing](#part-viii-conformance--testing)
  - [30. Testing Strategy](#30-testing-strategy)
  - [31. Conformance Harness Design](#31-conformance-harness-design)
  - [32. Performance Targets](#32-performance-targets)
- [Part IX: Risk Management](#part-ix-risk-management)
  - [33. Risk Summary Table](#33-risk-summary-table)
  - [34. Security Model](#34-security-model)
- [Part X: FrankenFS Parallel](#part-x-frankenfs-parallel)
  - [35. Methodology Correspondence](#35-methodology-correspondence)
- [Appendices](#appendices)
  - [A. Glossary](#a-glossary)
  - [B. Reference Materials](#b-reference-materials)
  - [C. Companion Document Status](#c-companion-document-status)

---

# Part I: Methodology

## 1. The Four-Document Methodology

FrankenSSH follows the same four-document methodology proven by the FrankenFS
project (a memory-safe Rust reimplementation of ext4/btrfs with block-level
MVCC and RaptorQ self-healing, plus quantitative parity tracking). The
methodology was designed to prevent the two failure modes of large-scale
rewrites:

1. **Line-by-line translation** — produces unidiomatic Rust that inherits C's
   design flaws without gaining Rust's safety guarantees.
2. **Clean-room without spec** — produces a system that doesn't interoperate
   with the legacy ecosystem because behavioral nuances were never captured.

The four documents, in dependency order:

| # | Document | Purpose | When Written |
|---|----------|---------|-------------|
| 1 | `EXISTING_SSH_STRUCTURE.md` | **Behavioral extraction** from legacy code. Documents WHAT the legacy system does (packet formats, state machines, algorithm negotiation, error conditions) without prescribing HOW to implement it in Rust. | Before any Rust code |
| 2 | `PROPOSED_ARCHITECTURE.md` | **Idiomatic Rust architecture.** Crate map, dependency DAG, trait hierarchy, data-flow diagrams. Designed from the behavioral spec, not from C's module structure. | After behavior extraction |
| 3 | `PLAN_TO_PORT_SSH_TO_RUST.md` | **Operational plan.** Scope, explicit exclusions, source metrics, phased delivery with acceptance criteria, cross-cutting concerns, risk register, success criteria. | After architecture design |
| 4 | `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md` | **Canonical normative specification.** Supersedes all other documents where conflicts exist. The single source of truth for what FrankenSSH MUST do. | Continuously maintained |

### 1.1 Document Lifecycle

- Documents 1-3 are written **before** significant implementation begins.
- Document 4 is the living normative spec — updated as implementation reveals
  behavioral nuances not captured in the initial extraction.
- All four documents are committed in the repository root.
- Any change that alters protocol behavior MUST update the relevant documents
  in the same commit.

### 1.2 Why This Works

The FrankenFS project demonstrated that this methodology:

- **Prevents scope ambiguity:** Features are either in-scope (with acceptance
  criteria) or explicitly excluded (with rationale). No gray area.
- **Enables parallel agent work:** Multiple agents can work on different crates
  simultaneously because the trait contracts are defined upfront.
- **Catches drift early:** The `FEATURE_PARITY.md` tracker and conformance
  harness CI gate prevent "it works on my machine" claims.
- **Preserves legacy-compatible behavior:** The behavioral extraction document
  captures the observable contract, so the Rust implementation can be validated
  against real OpenSSH instances.

---

## 2. Core Principles

These are non-negotiable, inherited from the FrankenFS methodology and adapted
for SSH:

### 2.1 Spec-First, Not Translation

> Never translate C line-by-line. Extract behavior into spec docs first, then
> implement from the spec.

OpenSSH's C code contains decades of accumulated workarounds, platform-specific
ifdefs, and intertwined concerns (crypto, protocol, I/O, config parsing all
in the same files). Translating it line-by-line would produce 110K lines of
unidiomatic Rust with no safety improvement.

Instead:
1. Extract the **observable behavior** (packet formats, state transitions,
   algorithm negotiation sequences, error responses).
2. Design an **idiomatic Rust architecture** from the behavioral spec.
3. Implement from the architecture spec.
4. Validate via conformance harness against real OpenSSH.

### 2.2 No Ambient Authority

Target architecture: every I/O operation accepts `&asupersync::Cx` as its first
parameter, providing:

- **Cooperative cancellation:** Operations check `cx.checkpoint()` at yield
  points. A cancelled Cx causes `FshError::Cancelled`.
- **Deadline propagation:** SSH operations have timeouts (e.g., authentication
  must complete within N seconds). Cx carries these deadlines.
- **Deterministic testing:** The asupersync lab runtime enables reproducible
  scheduling for testing race conditions in channel multiplexing.

Current bootstrap status note: `asupersync` integration is planned/deferred in
the workspace dependency snapshot; this section describes the intended contract.

### 2.3 Zero Unsafe Code

```rust
#![forbid(unsafe_code)]
```

At every crate root, enforced by workspace lint. Cryptographic primitives use
audited libraries (`ring`, `rustcrypto`) that encapsulate their own unsafe code
behind safe APIs.

### 2.4 Deterministic Testability

Concurrency-sensitive logic (channel multiplexing, rekey during data transfer,
window size management) MUST be testable under the asupersync lab runtime with
seed-controlled scheduling.

### 2.5 Proof-First for Risky Logic

High-risk subsystems (key exchange, authentication state machine, channel flow
control) require:
- Explicit invariants (what MUST remain true)
- Formal state diagrams (not just prose descriptions)
- Test vectors from RFCs (not hand-rolled test data)

---

## 3. Porting Doctrine

The porting sequence, applied to each subsystem:

```
1. Extract behavior into EXISTING_SSH_STRUCTURE.md
   (packet formats, state machines, algorithm lists, error conditions)
        |
        v
2. Design Rust architecture in PROPOSED_ARCHITECTURE.md
   (crate boundaries, traits, type-state encoding)
        |
        v
3. Implement idiomatically in Rust
   (from the spec, not from C)
        |
        v
4. Add conformance tests in fsh-harness
   (validate against real OpenSSH)
        |
        v
5. Update FEATURE_PARITY.md
   (quantitative tracking in the same commit)
```

### 3.1 Non-Negotiable Rules

1. **No line-by-line translation from C.** Extract behavior, then re-implement.
2. **No compatibility shims for bad designs.** If legacy behavior is insecure
   but observable (e.g., SSH-1 protocol), exclude it explicitly rather than
   implement it insecurely.
3. **Conformance harness is the arbiter.** Not vibes, not "it looks right."
4. **Every exclusion is documented.** Hidden exclusions are spec violations.
5. **Feature parity is quantitative.** Percentages and N/M counts, not prose.

---

## 4. Quality Controls

### 4.1 Compiler/Lint/Test Gates

After every substantive change:

```bash
cargo fmt --check
cargo check --all-targets
cargo clippy --all-targets -- -D warnings
cargo test --workspace
```

### 4.2 Workspace Lints

```toml
[workspace.lints.rust]
unsafe_code = "forbid"

[workspace.lints.clippy]
pedantic = { level = "deny", priority = -1 }
nursery = { level = "deny", priority = -1 }
# Selective allows for pragmatism:
module_name_repetitions = "allow"
missing_errors_doc = "allow"
missing_panics_doc = "allow"
```

### 4.3 Release Profile

```toml
[profile.release]
opt-level = "z"        # Size optimization
lto = true             # Link-time optimization
codegen-units = 1      # Single codegen unit
panic = "abort"        # Abort on panic
strip = true           # Strip symbols

[profile.release-perf]
inherits = "release"
opt-level = 3          # For benchmarking
```

### 4.4 CI Pipeline

| Gate | Tool | Failure Action |
|------|------|---------------|
| Format | `cargo fmt --check` | Block merge |
| Compile | `cargo check --all-targets` | Block merge |
| Lints | `cargo clippy --all-targets -- -D warnings` | Block merge |
| Tests | `cargo test --workspace` | Block merge |
| Conformance | `cargo test -p fsh-harness -- --nocapture` (scope-triggered) | Block merge on conformance changes |
| Parity | `parity_report_matches_feature_parity_md` | Block merge |
| Security | `cargo audit` | Advisory (warn only unless policy escalates) |
| Benchmarks | `cargo bench -p fsh-harness` (scope-triggered) | Advisory |

### 4.5 Alien-Artifact Quality Bar

For high-risk subsystems (key exchange, authentication, crypto selection),
prefer principled models over ad-hoc decisions:

- Formal state machine diagrams for protocol transitions
- RFC test vectors for every cryptographic operation
- Timing analysis for side-channel resistance
- Explicit threat models with trust boundary documentation

If a heuristic is used, document why formal alternatives were not viable.

---

# Part II: Project Identity

## 5. What FrankenSSH Is

FrankenSSH is a **memory-safe, clean-room Rust reimplementation of the SSH-2
protocol** that combines:

1. **Wire-compatible behavior** with OpenSSH — connects to and accepts
   connections from standard SSH clients and servers.
2. **Post-quantum hybrid key exchange** — ML-KEM-768 + X25519 protects against
   "harvest now, decrypt later" attacks by quantum computers.
3. **Compile-time protocol safety** — Rust's type system encodes the SSH
   protocol state machine so that invalid transitions (e.g., sending data
   before authentication) are compilation errors, not runtime bugs.

### 5.1 What FrankenSSH Is NOT

- Not a fork of OpenSSH. Zero lines of C code are copied.
- Not a wrapper around libssh/libssh2. Clean-room implementation.
- Not an SSH-1 implementation. SSH-1 is cryptographically broken.
- Not a replacement for OpenSSH's ecosystem tooling (ssh-keygen, ssh-copy-id,
  etc.) — at least not in v1.

---

## 6. Innovation Layer

Like FrankenFS (which adds MVCC and RaptorQ self-healing on top of ext4/btrfs
compatibility), FrankenSSH adds two innovations on top of SSH-2 wire
compatibility:

### 6.1 Post-Quantum Hybrid Key Exchange

**Problem:** Current SSH key exchanges (Curve25519, ECDH-P256) are vulnerable
to future quantum computers. An adversary can record encrypted SSH sessions
today and decrypt them when a Cryptographically Relevant Quantum Computer
(CRQC) becomes available — the "harvest now, decrypt later" threat.

**Solution:** Hybrid key exchange that combines a classical algorithm (X25519)
with a post-quantum algorithm (ML-KEM-768, formerly Kyber). The hybrid
construction ensures:

- **Forward security against classical adversaries:** If ML-KEM is broken
  classically, X25519 still provides security.
- **Forward security against quantum adversaries:** If X25519 is broken
  by a CRQC, ML-KEM still provides security.
- **Backward compatibility:** Servers/clients that don't support PQ KEX
  fall back to classical-only key exchange via standard SSH algorithm
  negotiation.

**Standard basis:**
- `draft-ietf-sshm-pq-ssh` (IETF SSH post-quantum drafts)
- NIST FIPS 203 (ML-KEM)
- Hybrid construction: `sntrup761x25519-sha512` (already in OpenSSH 9.0+)
  plus `mlkem768x25519-sha256` (emerging standard)

### 6.2 Type-State Protocol Machine

**Problem:** SSH protocol violations are a major source of security
vulnerabilities. In C implementations, the protocol state is tracked by
integer flags that can be checked incorrectly or forgotten entirely. Examples:

- CVE-2023-48795 (Terrapin attack): sequence number manipulation possible
  because the "strict KEX" mode state was not consistently enforced.
- CVE-2024-6387 (regreSSHion): signal handler race condition where
  authentication state was not properly tracked across async signals.

**Solution:** Encode the SSH protocol state machine in Rust's type system:

```rust
// These types exist at compile time only — zero runtime cost
pub struct Connected;        // TCP connected, no version exchange
pub struct VersionExchanged; // Version strings exchanged
pub struct KexInitExchanged; // KEXINIT exchanged, algorithms selected
pub struct KexRunning;       // Key exchange in progress
pub struct Encrypted;        // Key exchange complete, encryption active
pub struct Authenticating;   // ssh-userauth service accepted, auth in progress
pub struct Authenticated;    // User authenticated
pub struct Ready;            // Channels can be opened

pub struct Session<S: ProtocolState> {
    transport: Transport,
    _state: PhantomData<S>,
}

// You literally cannot call open_channel() on a Session<Encrypted>
// because the method only exists on Session<Authenticated> and Session<Ready>
impl Session<Encrypted> {
    pub fn request_service(self, cx: &Cx) -> Result<Session<Authenticating>>;
}

impl Session<Authenticating> {
    pub fn authenticate(self, cx: &Cx, ...) -> Result<Session<Authenticated>>;
}

impl Session<Ready> {
    pub fn open_channel(&self, cx: &Cx, ...) -> Result<ChannelId>;
}
```

The compiler enforces protocol ordering. There is no runtime state machine to
get wrong — invalid transitions simply don't compile.

---

## 7. Legacy Corpus

The behavioral extraction draws from these legacy implementations:

| Implementation | Language | LOC | Role |
|---------------|----------|-----|------|
| OpenSSH 9.x (`ssh/`, `sshd/`, shared) | C | ~110,000 | Primary reference: most deployed SSH implementation |
| Dropbear 2024.x | C | ~25,000 | Lightweight reference: embedded/minimal SSH |
| libssh2 1.x | C | ~30,000 | Library API reference: embedding SSH in applications |
| **Total** | | **~165,000** | |

Primary extraction source: **OpenSSH** — because it defines the de facto
standard behavior that every SSH client/server must be compatible with.

### 7.1 OpenSSH Source Navigation

| Path | Domain |
|------|--------|
| `packet.c` | Binary packet framing, sequence numbers, encryption/MAC application |
| `kex.c`, `kexgen.c`, `kexdh.c`, `kexecdh.c`, `kexsntrup761x25519.c` | Key exchange algorithms and dispatch |
| `cipher.c`, `cipher-chachapoly.c`, `cipher-aesctr.c` | Cipher implementations and AEAD wrappers |
| `mac.c`, `umac.c`, `hmac.c` | MAC algorithm implementations |
| `auth.c`, `auth2.c`, `auth2-pubkey.c`, `auth2-passwd.c` | Authentication protocol |
| `sshkey.c`, `sshkey-xmss.c`, `ssh-ed25519.c`, `ssh-rsa.c` | Key types, parsing, signing, verification |
| `channels.c`, `channel.h` | Channel multiplexing, window management, forwarding |
| `session.c`, `serverloop.c` | Server-side session lifecycle |
| `sftp-server.c`, `sftp-client.c`, `sftp-common.c` | SFTP subsystem |
| `ssh-agent.c`, `authfd.c` | Key agent protocol |
| `readconf.c`, `servconf.c` | Configuration file parsing |
| `sshbuf.c`, `sshbuf-getput-basic.c`, `sshbuf-getput-crypto.c` | Secure buffer management |

---

## 8. RFC Corpus

These RFCs define the normative protocol behavior:

### 8.1 Core Protocol

| RFC | Title | Relevance |
|-----|-------|-----------|
| RFC 4251 | SSH Protocol Architecture | Overall architecture, data types, naming conventions |
| RFC 4252 | SSH Authentication Protocol | Authentication methods, partial success, banner |
| RFC 4253 | SSH Transport Layer Protocol | Version exchange, KEX, encryption, MAC, compression, rekey |
| RFC 4254 | SSH Connection Protocol | Channels, sessions, forwarding, signals, exit status |

### 8.2 Authentication Extensions

| RFC | Title | Relevance |
|-----|-------|-----------|
| RFC 4256 | Keyboard-Interactive Authentication | Generic challenge-response mechanism |
| RFC 4462 | GSSAPI Authentication (excluded) | Listed for exclusion documentation |
| RFC 6187 | X.509v3 Certificates for SSH | Certificate-based authentication |

### 8.3 Cryptographic Algorithms

| RFC | Title | Relevance |
|-----|-------|-----------|
| RFC 5656 | ECDSA and ECDH for SSH | Elliptic curve key exchange and signatures |
| RFC 8308 | Extension Negotiation in SSH | `ext-info-s`/`ext-info-c` mechanism |
| RFC 8332 | RSA SHA-2 Signatures | `rsa-sha2-256`, `rsa-sha2-512` |
| RFC 8709 | Ed25519 and Ed448 Keys | EdDSA key types |
| RFC 8731 | Curve25519/448 Key Exchange | `curve25519-sha256` |
| RFC 9142 | Key Exchange (Curve25519, Curve448) | Updated KEX algorithms |

### 8.4 SFTP

| RFC/Draft | Title | Relevance |
|-----------|-------|-----------|
| draft-ietf-secsh-filexfer-02 | SFTP v3 | Most widely deployed SFTP version |
| draft-ietf-secsh-filexfer-13 | SFTP v6 | Latest draft; extended operations |

### 8.5 Post-Quantum

| Draft | Title | Relevance |
|-------|-------|-----------|
| draft-ietf-sshm-pq-ssh | Post-Quantum Key Exchange for SSH | ML-KEM hybrid construction |
| FIPS 203 | ML-KEM (Module-Lattice Key Encapsulation) | PQ KEM standard |

---

# Part III: Architecture

## 9. 15-Crate Workspace

| # | Crate | Role | Key Dependencies | Primary Phase |
|---|-------|------|-----------------|--------------|
| 1 | `fsh-types` | Newtypes: `SessionId`, `ChannelId`, `SeqNum`, `MessageType`, `WindowSize`, `DisconnectReason`; binary read/write helpers (`read_u32`, `read_bool`, `read_string`, `read_name_list`, `read_mpint`, `write_u32`, `write_bool`, `write_string`, `write_mpint`, `write_name_list`); SSH constants | `serde`, `thiserror` | 2 |
| 2 | `fsh-error` | `FshError` enum with SSH disconnect reason code mapping; `Result<T>` alias | `thiserror` | 2 |
| 3 | `fsh-wire` | Pure packet parsing/serialization (no I/O): `SshPacket`, `MessageType` dispatch, all SSH message structs; padding; `WirePacket` trait | `fsh-types`, `fsh-error`, `serde` | 2 |
| 4 | `fsh-crypto` | Cipher suite abstraction: `CipherSuite` trait, `chacha20-poly1305@openssh.com`, `aes256-gcm@openssh.com`, `aes256-ctr`+`hmac-sha2-256`; key derivation (`kdf_hash`); host key types (Ed25519, RSA-SHA2, ECDSA); hybrid PQ KEX (ML-KEM-768 + X25519 planned) | `fsh-types`, `fsh-error`, `ring`, `chacha20poly1305`, `aes-gcm`, `x25519-dalek`, `ed25519-dalek`, `sha2` | 3 |
| 5 | `fsh-transport` | SSH transport layer: version exchange, algorithm negotiation, key exchange orchestration, `Transport<S>` type-state machine, rekey, sequence number management, `EncryptedTransport` (encrypt/decrypt/MAC per-packet) | `fsh-types`, `fsh-error`, `fsh-wire`, `fsh-crypto`, `asupersync` (planned) | 4 |
| 6 | `fsh-auth` | Authentication protocol: `Authenticator` trait, pubkey auth, password auth, keyboard-interactive, certificate validation; partial success handling; auth banner; attempt limiting | `fsh-types`, `fsh-error`, `fsh-wire`, `fsh-crypto`, `fsh-transport` | 5 |
| 7 | `fsh-channel` | Channel multiplexing: `ChannelManager`, channel open/close/data/EOF/window-adjust; flow control (window size management); channel types (session, direct-tcpip, forwarded-tcpip) | `fsh-types`, `fsh-error`, `fsh-wire`, `fsh-transport`, `asupersync` (planned) | 5 |
| 8 | `fsh-session` | Session channel operations: PTY allocation, command exec, env vars, signal forwarding, exit status/signal, subsystem dispatch | `fsh-types`, `fsh-error`, `fsh-channel`, `asupersync` (planned) | 6 |
| 9 | `fsh-sftp` | SFTP subsystem: v3 (mandatory) and v6 (optional) protocol, file handle management, stat/read/write/rename/symlink/mkdir/rmdir, request-response correlation | `fsh-types`, `fsh-error`, `fsh-wire`, `fsh-channel`, `asupersync` (planned) | 6 |
| 10 | `fsh-forward` | Port forwarding: local (`direct-tcpip`), remote (`forwarded-tcpip`), dynamic (SOCKS5 proxy); forwarding channel lifecycle | `fsh-types`, `fsh-error`, `fsh-channel`, `asupersync` (planned) | 6 |
| 11 | `fsh-agent` | SSH agent protocol: key listing (`SSH2_AGENTC_REQUEST_IDENTITIES`), signing (`SSH2_AGENTC_SIGN_REQUEST`), key add/remove, key constraints (lifetime, confirm); agent connection management | `fsh-types`, `fsh-error`, `fsh-wire`, `fsh-crypto`, `asupersync` (planned) | 6 |
| 12 | `fsh-server` | SSH server (sshd equivalent): TCP listener, per-connection session management, host key loading, auth dispatch, subsystem dispatch, privilege separation model | `fsh-types`, `fsh-error`, `fsh-transport`, `fsh-auth`, `fsh-channel`, `fsh-session`, `tokio` | 7 |
| 13 | `fsh-client` | SSH client (ssh equivalent): connection establishment, config parsing, known_hosts management, agent forwarding, multiplexed connection sharing, interactive/batch mode | `fsh-types`, `fsh-error`, `fsh-transport`, `fsh-auth`, `fsh-channel`, `fsh-session`, `fsh-agent`, `tokio` | 7 |
| 14 | `fsh-harness` | Conformance test harness: automated testing against real OpenSSH client/server; RFC test vectors; fuzz targets; performance benchmarks | `frankenssh`, `fsh-wire`, `fsh-crypto`, `serde`, `serde_json`, `criterion`, `proptest` | 8 |
| 15 | `frankenssh` | Public API facade: re-exports core functionality; stable external interface for embedding FrankenSSH as a library | `fsh-transport`, `fsh-auth`, `fsh-channel`, `fsh-session`, `fsh-sftp`, `fsh-forward`, `fsh-agent` | 8 |

---

## 10. Dependency Graph

```
                    +------------+  +------------+
                    | fsh-types  |  | fsh-error  |
                    +-----+------+  +------+-----+
                          |                |
                          +-------+--------+
                                  |
                    +-------------+-------------+
                    |                           |
              +-----v------+             +------v------+
              |  fsh-wire  |             |  fsh-crypto |
              |  (no I/O)  |             |  (ring etc) |
              +-----+------+             +------+------+
                    |                           |
                    +-----------+---------------+
                                |
                       +--------v--------+
                       |  fsh-transport  |
                       |  (type-state)   |
                       +--------+--------+
                                |
                    +-----------+-----------+
                    |                       |
              +-----v------+         +------v------+
              |  fsh-auth  |         | fsh-channel |
              +-----+------+         +------+------+
                    |                       |
                    |          +--------+---+--------+---------+
                    |          |        |            |         |
                    |   +------v---+ +--v-------+ +-v------+ +v---------+
                    |   | session  | |  sftp    | |forward | |  agent   |
                    |   +------+---+ +--+-------+ +-+------+ ++---------+
                    |          |        |            |         |
                    +----+-----+--------+------------+---------+
                         |
              +----------+----------+
              |                     |
        +-----v------+      +------v------+
        | fsh-server |      | fsh-client  |
        +-----+------+      +------+------+
              |                     |
              +---------+-----------+
                        |
                  +-----------+      +--------------+
                  |frankenssh |      | fsh-harness  |
                  | (facade)  |------| (conformance)|
                  +-----------+      +--------------+
```

### 10.1 Layering Rules

1. **`fsh-wire` is pure.** No I/O, no async, no network. Parse bytes in,
   produce structs. Serialize structs, produce bytes.
2. **`fsh-crypto` does not know about SSH framing.** It provides cipher
   suites, key derivation, and signing — but never touches packet structure.
3. **`fsh-transport` owns the state machine.** It is the only crate that
   knows about protocol state transitions.
4. **`fsh-auth` and `fsh-channel` depend on `fsh-transport` but not on
   each other.** They can be developed in parallel.
5. **Domain crates (session, sftp, forward, agent) depend on `fsh-channel`
   but not on `fsh-transport` directly.** They see channels, not raw transport.
6. **`fsh-server` and `fsh-client` are integration crates.** They wire
   together the domain crates but contain minimal business logic.
7. **`fsh-harness` depends on `frankenssh` (the public facade) and tests the
   external interface, not internals.**

---

## 11. Key Traits

### 11.1 Wire-Level Parsing

```rust
/// Pure parse/serialize for SSH messages. No I/O.
pub trait WirePacket: Sized {
    /// SSH message type number (RFC 4253 §12).
    const MESSAGE_TYPE: u8;

    /// Parse from raw bytes (after decryption + MAC verification).
    fn parse(payload: &[u8]) -> Result<Self, ParseError>;

    /// Serialize to bytes (before encryption + MAC).
    fn serialize(&self, out: &mut Vec<u8>) -> Result<(), ParseError>;
}
```

### 11.2 Cipher Suite

```rust
/// Encryption/decryption abstraction. Implementations: chacha20-poly1305,
/// aes256-gcm, aes256-ctr + hmac.
pub trait CipherSuite: Send + Sync {
    /// Encrypt a plaintext payload with associated sequence number.
    fn encrypt(&self, seq: u32, payload: &[u8], out: &mut Vec<u8>) -> Result<()>;

    /// Decrypt ciphertext, verify integrity, return plaintext.
    fn decrypt(&self, seq: u32, data: &[u8], out: &mut Vec<u8>) -> Result<()>;

    /// MAC length in bytes (0 for AEAD ciphers like GCM/Poly1305).
    fn mac_len(&self) -> usize;

    /// Cipher block size for padding calculation.
    fn block_size(&self) -> usize;

    /// Is this an AEAD cipher (integrated MAC)?
    fn is_aead(&self) -> bool;
}
```

### 11.3 Key Exchange

```rust
/// Key exchange algorithm abstraction.
pub trait KexAlgorithm: Send {
    /// Algorithm name as it appears in algorithm negotiation.
    fn name(&self) -> &str;

    /// Generate ephemeral key pair; return client's public contribution.
    fn generate(&mut self) -> Result<Vec<u8>>;

    /// Compute shared secret from peer's public contribution.
    fn compute_shared_secret(&mut self, peer_public: &[u8]) -> Result<Vec<u8>>;

    /// Hash function used for this KEX (SHA-256, SHA-512, etc.).
    fn hash_algorithm(&self) -> HashAlgorithm;

    /// Is this a post-quantum hybrid algorithm?
    fn is_post_quantum(&self) -> bool;
}
```

### 11.4 Authenticator

```rust
/// Server-side authentication method.
pub trait Authenticator: Send + Sync {
    /// Method name (e.g., "publickey", "password", "keyboard-interactive").
    fn method_name(&self) -> &str;

    /// Attempt authentication. Returns Ok(true) for success, Ok(false) for
    /// failure, Err for protocol errors.
    fn authenticate(
        &self,
        cx: &Cx,
        username: &str,
        request: &AuthRequest,
    ) -> Result<AuthResult>;
}

pub enum AuthResult {
    Success,
    Failure { partial_success: bool },
    ContinueWithMethods(Vec<String>),
}
```

### 11.5 Channel Handler

```rust
/// Handles events on a multiplexed SSH channel.
pub trait ChannelHandler: Send {
    /// Called when data arrives on the channel.
    fn on_data(&mut self, cx: &Cx, data: &[u8]) -> Result<()>;

    /// Called when extended data arrives (e.g., stderr).
    fn on_extended_data(&mut self, cx: &Cx, data_type: u32, data: &[u8]) -> Result<()>;

    /// Called when the remote side sends EOF.
    fn on_eof(&mut self, cx: &Cx) -> Result<()>;

    /// Called when the channel is closed.
    fn on_close(&mut self, cx: &Cx) -> Result<()>;

    /// Called when a channel request arrives (e.g., pty-req, exec, env).
    fn on_request(&mut self, cx: &Cx, request: &ChannelRequest) -> Result<bool>;
}
```

---

## 12. Error Model

### 12.1 `FshError` Enum

Illustrative baseline shape (exact variant inventory may grow as long as
Section 12.2 mapping guarantees remain deterministic).

```rust
#[derive(Debug, thiserror::Error)]
pub enum FshError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    #[error("protocol violation: {0}")]
    Protocol(String),

    #[error("packet parse error: {0}")]
    Parse(#[from] ParseError),

    #[error("cryptographic error: {0}")]
    Crypto(String),

    #[error("authentication failed: {0}")]
    AuthFailed(String),

    #[error("key exchange failed: {0}")]
    KexFailed(String),

    #[error("channel error: {0}")]
    Channel(String),

    #[error("connection disconnected: {reason}")]
    Disconnected { reason: DisconnectReason, description: String },

    #[error("operation cancelled")]
    Cancelled,

    #[error("timeout")]
    Timeout,

    #[error("host key verification failed")]
    HostKeyVerification,

    #[error("unsupported algorithm: {0}")]
    UnsupportedAlgorithm(String),

    #[error("configuration error: {0}")]
    Config(String),

    #[error("agent error: {0}")]
    Agent(String),

    #[error("sftp error: status={status_code}")]
    Sftp { status_code: u32, message: String },

    #[error("permission denied")]
    PermissionDenied,

    #[error("not found: {0}")]
    NotFound(String),
}
```

### 12.2 SSH Disconnect Reason Mapping

Every externally observable `FshError` class maps to an SSH disconnect reason
code (RFC 4253 §11.1):

| FshError Class / Variant | SSH Disconnect Reason | Code |
|-----------------|----------------------|------|
| `Protocol` | `SSH_DISCONNECT_PROTOCOL_ERROR` | 2 |
| `KexFailed` | `SSH_DISCONNECT_KEY_EXCHANGE_FAILED` | 3 |
| `UnsupportedAlgorithm` | `SSH_DISCONNECT_KEY_EXCHANGE_FAILED` | 3 |
| `Crypto` | `SSH_DISCONNECT_MAC_ERROR` | 5 |
| `ServiceNotAvailable` | `SSH_DISCONNECT_SERVICE_NOT_AVAILABLE` | 7 |
| `VersionMismatch` | `SSH_DISCONNECT_PROTOCOL_VERSION_NOT_SUPPORTED` | 8 |
| `HostKeyVerification` | `SSH_DISCONNECT_HOST_KEY_NOT_VERIFIABLE` | 9 |
| `ConnectionLost` | `SSH_DISCONNECT_CONNECTION_LOST` | 10 |
| `Timeout` | `SSH_DISCONNECT_BY_APPLICATION` | 11 |
| `Cancelled` | `SSH_DISCONNECT_BY_APPLICATION` | 11 |
| `TooManyConnections` | `SSH_DISCONNECT_TOO_MANY_CONNECTIONS` | 12 |
| `AuthCancelled` | `SSH_DISCONNECT_AUTH_CANCELLED_BY_USER` | 13 |
| `AuthFailed` | `SSH_DISCONNECT_NO_MORE_AUTH_METHODS_AVAILABLE` | 14 |

---

## 13. Type-State Protocol Machine

The SSH-2 protocol has a strict ordering of phases. FrankenSSH encodes this
ordering at the type level:

### 13.1 State Diagram

```
  [TCP Connected]
        |
        v
  [VersionExchanged]  -- exchange SSH-2.0 version strings
        |
        v
  [KexInitExchanged] --- exchange KEXINIT + select algorithms
        |
        v
  [KexRunning]  --------- perform KEX, derive keys, exchange NEWKEYS
        |
        v
  [Encrypted]  ----------- transport encrypted, service request possible
        |
        v
  [Authenticating]  ------ user authentication in progress
        |
        v
  [Authenticated]  ------- auth complete, channels available
        |
        v
  [Ready]  --------------- channels open, data flowing
        |
        v
  [Closing]  ------------ disconnect path in progress
        |
        v
  [Disconnected]  -------- connection closed
```

### 13.2 Type-State Encoding

```rust
// Protocol states (zero-sized types — exist only at compile time)
pub struct Connected;
pub struct VersionExchanged;
pub struct KexInitExchanged;
pub struct KexRunning;
pub struct Encrypted;
pub struct Authenticating;
pub struct Authenticated;
pub struct Ready;
pub struct Closing;
pub struct Disconnected;

// Session is parameterized by state
pub struct Session<S: ProtocolState> {
    stream: TcpStream,
    state_data: S::Data,
    _marker: PhantomData<S>,
}

// State transitions consume self and return the next state.
// This prevents use-after-transition.
impl Session<Connected> {
    pub async fn exchange_version(self, cx: &Cx) -> Result<Session<VersionExchanged>>;
}

impl Session<VersionExchanged> {
    pub async fn exchange_kexinit(self, cx: &Cx) -> Result<Session<KexInitExchanged>>;
}

impl Session<KexInitExchanged> {
    pub async fn run_kex(self, cx: &Cx) -> Result<Session<KexRunning>>;
}

impl Session<KexRunning> {
    pub async fn install_keys(self, cx: &Cx) -> Result<Session<Encrypted>>;
}

impl Session<Encrypted> {
    pub async fn request_userauth_service(self, cx: &Cx)
        -> Result<Session<Authenticating>>;
}

impl Session<Authenticating> {
    pub async fn authenticate(self, cx: &Cx, auth: &dyn Authenticator)
        -> Result<Session<Authenticated>>;
}

impl Session<Authenticated> {
    pub async fn ready(self, cx: &Cx) -> Result<Session<Ready>>;
}

impl Session<Ready> {
    pub async fn open_channel(&self, cx: &Cx, kind: ChannelKind)
        -> Result<ChannelId>;
    pub async fn disconnect(self, cx: &Cx) -> Result<Session<Closing>>;
}

impl Session<Closing> {
    pub async fn finalize(self, cx: &Cx) -> Result<Session<Disconnected>>;
}
```

### 13.3 Rekey

Rekeying can happen at any point after `Encrypted`. The type-state handles
this by providing a `rekey()` method on all post-Encrypted states that
performs KEX inline without changing the session state type:

```rust
impl<S: PostEncryptionState> Session<S> {
    pub async fn rekey(&mut self, cx: &Cx) -> Result<()>;
}
```

---

# Part IV: Scope

## 14. Deliverables

| Deliverable | Description |
|------------|-------------|
| 15-crate Cargo workspace | Modular, independently testable crates |
| SSH server binary (`fsh-server`) | Accepts SSH connections, serves shell/SFTP/forwarding |
| SSH client binary (`fsh-client`) | Connects to SSH servers, interactive and batch mode |
| Public API library (`frankenssh`) | Embeddable SSH for other Rust programs |
| Conformance harness (`fsh-harness`) | Automated testing against real OpenSSH |
| SFTP subsystem | File transfer compatible with any SFTP client/server |
| SSH agent | Key management compatible with `ssh-add` / `ssh-agent` |

---

## 15. Explicit Exclusions

| Exclusion | Rationale |
|-----------|-----------|
| **SSH-1 protocol** | Cryptographically broken; removed from OpenSSH. Zero security value. |
| **X11 forwarding** | Archaic mechanism (<1% usage); massive attack surface (X11 protocol is unencrypted locally); replaced by Wayland. |
| **GSSAPI/Kerberos auth** | Enterprise-specific; complex; can be added as external plugin. |
| **Legacy ciphers (3DES, Blowfish, RC4, CAST128, arcfour)** | Cryptographically weak or broken; OpenSSH already deprecating. Only modern ciphers (ChaCha20-Poly1305, AES-256-GCM, AES-256-CTR). |
| **DSA keys** | NIST deprecated; OpenSSH disabled by default since 9.8. |
| **Host-based authentication** | Rarely used; depends on rsh-like trust model that's fundamentally insecure. |
| **Compression (zlib, zlib@openssh.com)** | CRIME/BREACH-style attack surface; marginal benefit on modern networks; can add in future phase if needed. |
| **SSH-keygen/ssh-copy-id tooling** | Utility scripts, not core protocol. Can be added in Phase 9+ or as separate binaries. |
| **ProxyJump/ProxyCommand** | Client UX feature, not protocol. Can be added in client polish phase. |
| **ControlMaster multiplexing** | OpenSSH-specific Unix socket multiplexing. Can be added later. |

---

## 16. Target Platform

- **OS:** Linux (x86_64, aarch64) primary; macOS secondary
- **Rust edition:** 2024
- **MSRV:** 1.85 (required by Edition 2024)
- **Async runtime:** `tokio` for production I/O; `asupersync` is planned for
  deterministic lab testing and is currently deferred/commented in workspace dependencies

---

## 17. Key Dependencies

| Crate | Role | Version Pin |
|-------|------|-------------|
| `asupersync` | Cx capability contexts, cooperative cancellation, lab runtime (planned/deferred in current workspace snapshot) | workspace path (deferred) |
| `tokio` | Async TCP I/O, production runtime | ^1 |
| `ring` | Cryptographic primitives (AES-GCM, SHA-2, HMAC, RSA verify) | ^0.17 |
| `chacha20poly1305` | ChaCha20-Poly1305 AEAD | ^0.10 |
| `x25519-dalek` | X25519 ECDH key exchange | ^2 |
| `ed25519-dalek` | Ed25519 key signing/verification | ^2 |
| `ml-kem` | ML-KEM-768 post-quantum KEM (NIST FIPS 203) | planned (crate selection deferred) |
| `sha2` | SHA-256/SHA-512 hash functions | ^0.10 |
| `aes-gcm` | AES-256-GCM AEAD | ^0.10 |
| `serde` + `serde_json` | Configuration, fixtures, diagnostics | ^1 |
| `thiserror` | Error derive macro | ^2 |
| `clap` | CLI argument parsing | ^4 |
| `tracing` | Structured logging | ^0.1 |
| `proptest` | Property-based testing | ^1 |
| `criterion` | Benchmarking | ^0.5 |

---

# Part V: Phased Delivery

## 18. Eight Phases

### Phase 1: Bootstrap

**Goal:** Establish the Cargo workspace, create all 15 crate stubs, write the
four specification documents, verify compilation.

**Deliverables:**
- `Cargo.toml` (workspace root)
- 15 crate stubs with correct inter-crate dependencies
- `EXISTING_SSH_STRUCTURE.md` (initial extraction)
- `PROPOSED_ARCHITECTURE.md` (crate topology)
- `PLAN_TO_PORT_SSH_TO_RUST.md` (this plan)
- `AGENTS.md` (agent guidelines)

**Acceptance Criteria:**
- `cargo check --workspace` exits 0
- `cargo test --workspace` exits 0
- All spec documents committed

**LOC:** ~300 | **Duration:** 1-2 days

---

### Phase 2: Types & Wire Format

**Goal:** Define all fundamental types and implement SSH binary packet
parsing/serialization with round-trip fidelity.

**Deliverables:**

| Crate | Key Items |
|-------|-----------|
| `fsh-types` | `SessionId(u64)`, `ChannelId(u32)`, `SeqNum(u32)`, `WindowSize(u32)`, `MessageType(u8)`, `DisconnectReason(u32)`; binary helpers (`read_u32`, `read_bool`, `read_string`, `read_name_list`, `read_mpint`, `write_u32`, `write_bool`, `write_string`, `write_mpint`, `write_name_list`) |
| `fsh-error` | `FshError`/`ParseError` taxonomy, `Result<T>` alias, SSH disconnect reason mapping |
| `fsh-wire` | All SSH message types as Rust structs implementing `WirePacket`: `KexInit`, `KexDhInit`, `KexDhReply`, `NewKeys`, `ExtInfo`, `ServiceRequest`, `ServiceAccept`, `UserAuthRequest`, `UserAuthSuccess`, `UserAuthFailure`, `UserAuthBanner`, `ChannelOpen`, `ChannelOpenConfirmation`, `ChannelOpenFailure`, `ChannelData`, `ChannelExtendedData`, `ChannelWindowAdjust`, `ChannelEof`, `ChannelClose`, `ChannelRequest`, `ChannelSuccess`, `ChannelFailure`, `GlobalRequest`, `RequestSuccess`, `RequestFailure`, `Disconnect`, `Ignore`, `Unimplemented`, `Debug` |

**Parsing Strategy:**
- Manual byte-level parsing via `fsh-types` helpers.
- SSH is big-endian (network byte order) — opposite of ext4.
- `read_bool` normalizes non-zero input to `true`; `write_bool` emits only 0 or 1.
- `read_string` returns `&[u8]` with length prefix (u32 length + data).
- `read_mpint` handles SSH multi-precision integers (sign-extended, big-endian).
- Context-dependent ranges (30-49 for KEX, 60-79 for auth) keep method-specific
  payload opaque in Phase 2; semantic decoding is deferred to later phases.
- All message types define `MESSAGE_TYPE` with the RFC-defined message number.

**Acceptance Criteria:**
- Parse and re-serialize every SSH message type; byte-for-byte round-trip.
- Parse real SSH traffic captured from an OpenSSH handshake.
- Property-based tests via `proptest`: random valid messages round-trip.
- Fuzz: `cargo-fuzz` target for packet parsing (no panics on arbitrary input).

**LOC:** ~4,000 | **Duration:** 1-2 weeks

**Risks:**

| Risk | Severity | Mitigation |
|------|----------|-----------|
| mpint encoding edge cases (negative numbers, leading zeros) | Medium | RFC 4251 §5 test vectors; proptest with boundary values |
| name-list parsing (comma-separated algorithm lists) | Low | Extensive test vectors from real OpenSSH negotiation |

---

### Phase 3: Crypto

**Goal:** Implement cipher suite abstraction and all required cryptographic
algorithms, including the post-quantum hybrid key exchange.

**Deliverables:**

| Component | Description |
|-----------|-------------|
| `CipherSuite` trait | Encrypt/decrypt/MAC abstraction |
| `ChaCha20Poly1305Suite` | `chacha20-poly1305@openssh.com` (OpenSSH's default) |
| `Aes256GcmSuite` | `aes256-gcm@openssh.com` (AEAD) |
| `Aes256CtrHmacSuite` | `aes256-ctr` + `hmac-sha2-256` (encrypt-then-MAC) |
| `Curve25519Kex` | `curve25519-sha256` key exchange |
| `MlKem768X25519Kex` | Hybrid ML-KEM-768 + X25519 (post-quantum) |
| Key derivation | `derive_keys()` per RFC 4253 §7.2 (HASH(K \|\| H \|\| X \|\| session_id)) |
| Host key types | Ed25519, RSA-SHA2-256/512, ECDSA-SHA2-nistp256 |
| `HostKey` trait | Sign/verify abstraction for host key operations |

**Acceptance Criteria:**
- ChaCha20-Poly1305: encrypt + decrypt with RFC test vectors.
- AES-256-GCM: encrypt + decrypt with NIST test vectors.
- Key derivation: derive keys from known K, H, session_id; compare against
  OpenSSH-derived keys.
- X25519 KEX: compute shared secret from known keypairs; verify against
  RFC 7748 test vectors.
- ML-KEM-768: encapsulate + decapsulate with FIPS 203 test vectors.
- Hybrid KEX: verify shared secret = SHA-256(X25519_secret || ML-KEM_secret).
- Ed25519 sign/verify: RFC 8032 test vectors.
- Constant-time verification: run `dudect`-style timing tests on MAC
  comparison.

**LOC:** ~3,000 | **Duration:** 2-3 weeks

**Risks:**

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Side-channel leaks in crypto | Critical | Use audited libraries only; never implement primitives; timing tests in CI |
| ML-KEM standard not yet finalized for SSH | High | Implement behind feature flag; hybrid ensures fallback to classical |
| Key derivation interop with OpenSSH | High | Capture real OpenSSH session keys (debug mode) and verify derivation matches |

---

### Phase 4: Transport

**Goal:** Implement the SSH transport layer with type-state protocol machine,
algorithm negotiation, key exchange, and encrypted packet I/O.

**Deliverables:**

| Component | Description |
|-----------|-------------|
| `VersionExchange` | Parse/send `SSH-2.0-FrankenSSH_0.1` version string |
| `AlgorithmNegotiation` | `KexInit` exchange; strict-KEX OpenSSH extension handling (`kex-strict-c-v00@openssh.com` / `kex-strict-s-v00@openssh.com`) |
| `KeyExchange` | Orchestrate KEX: generate ephemeral keys, exchange, derive session keys, verify host key, send `NewKeys` |
| `Transport<S>` | Type-state session with `Connected` -> `VersionExchanged` -> `KexInitExchanged` -> `KexRunning` -> `Encrypted` transitions |
| `EncryptedTransport` | Per-packet encrypt/decrypt with sequence number management |
| `Rekey` | Automatic rekeying after N bytes or N seconds (configurable) |

**Acceptance Criteria:**
- Complete handshake with real OpenSSH server (`sshd -d` debug mode).
- Complete handshake with real OpenSSH client (`ssh -vvv` verbose mode).
- Negotiate `chacha20-poly1305@openssh.com` + `curve25519-sha256`.
- Negotiate `aes256-gcm@openssh.com` + `curve25519-sha256`.
- Rekey after 1GB of data transfer; verify no data loss during rekey.
- Strict KEX mode: verify protection against Terrapin-style attacks.
- Type-state: verify that calling `open_channel()` on `Session<Encrypted>`
  produces a compilation error.

**LOC:** ~5,000 | **Duration:** 2-3 weeks

**Risks:**

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Algorithm negotiation order sensitivity | High | Follow RFC 4253 §7.1 strictly; test with restrictive algorithm configs |
| Rekey during data transfer | High | Buffer data during rekey; test with continuous transfer + forced rekey |
| Strict KEX interop | Medium | Test against OpenSSH 9.6+ which supports strict KEX |

---

### Phase 5: Auth & Channels

**Goal:** Implement SSH authentication protocol and channel multiplexing.

**Deliverables:**

| Crate | Key Items |
|-------|-----------|
| `fsh-auth` | `PubkeyAuthenticator` (Ed25519, RSA-SHA2, ECDSA), `PasswordAuthenticator`, `KeyboardInteractiveAuthenticator`, `CertificateAuthenticator`; auth banner; partial success; max attempts (default 6); `AuthDispatcher` for server-side method routing |
| `fsh-channel` | `ChannelManager` (allocate/free channel IDs, dispatch data), `Channel` struct (local_id, remote_id, window sizes, state), window adjust logic, `ChannelKind` enum (Session, DirectTcpip, ForwardedTcpip, AuthAgent), channel open rejection with reason codes |

**Acceptance Criteria:**
- Authenticate to OpenSSH server with Ed25519 pubkey.
- Authenticate to OpenSSH server with password.
- Authenticate with keyboard-interactive (PAM-style).
- FrankenSSH server authenticates OpenSSH client with pubkey.
- Open 100 simultaneous channels; verify independent data streams.
- Window management: send data exceeding window size; verify flow control
  pauses sender until `WINDOW_ADJUST` received.
- Channel close: verify CLOSE behavior both with and without prior EOF
  (RFC 4254 §5.3), including the common EOF -> CLOSE -> response choreography.

**LOC:** ~5,000 | **Duration:** 2-3 weeks

**Risks:**

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Auth method ordering (partial success logic) | Medium | Exhaustive test matrix: pubkey-then-password, pubkey-only, none-then-pubkey |
| Channel ID exhaustion | Low | u32 channel IDs recycled; test with rapid open/close cycles |
| Window size deadlock | High | Implement window adjustment proactively; test with asymmetric window sizes |

---

### Phase 6: Session & Subsystems

**Goal:** Implement session management, SFTP, port forwarding, and agent
protocol.

**Deliverables:**

| Crate | Key Items |
|-------|-----------|
| `fsh-session` | PTY allocation (`pty-req`), command execution (`exec`), shell (`shell`), environment variables (`env`), signal forwarding (`signal`), exit status (`exit-status`), exit signal (`exit-signal`), subsystem dispatch (`subsystem`) |
| `fsh-sftp` | SFTP v3 protocol: `SSH_FXP_INIT`/`VERSION`, `OPEN`, `CLOSE`, `READ`, `WRITE`, `STAT`, `FSTAT`, `LSTAT`, `SETSTAT`, `OPENDIR`, `READDIR`, `REMOVE`, `MKDIR`, `RMDIR`, `REALPATH`, `RENAME`, `READLINK`, `SYMLINK`; file handle management; request-ID correlation |
| `fsh-forward` | Local forwarding (`direct-tcpip`), remote forwarding (`forwarded-tcpip`, `tcpip-forward` global request), dynamic forwarding (SOCKS5 proxy) |
| `fsh-agent` | `SSH2_AGENTC_REQUEST_IDENTITIES`, `SSH2_AGENTC_SIGN_REQUEST`, `SSH2_AGENTC_ADD_IDENTITY`, `SSH2_AGENTC_REMOVE_IDENTITY`, `SSH2_AGENTC_REMOVE_ALL_IDENTITIES`; key constraints (lifetime, confirm) |

**Acceptance Criteria:**
- `fsh-client` opens interactive shell on OpenSSH server; PTY works correctly.
- `fsh-client` executes `echo hello` on OpenSSH server; captures stdout.
- SFTP: transfer 1GB file via `fsh-sftp` client to OpenSSH sftp-server; verify
  SHA-256 checksum.
- SFTP: `ls`, `mkdir`, `rmdir`, `rename`, `symlink` all work correctly.
- Local forwarding: `fsh-client -L 8080:localhost:80` forwards HTTP traffic.
- Remote forwarding: `fsh-client -R 9090:localhost:80` works with OpenSSH.
- Agent: `fsh-agent` serves keys to OpenSSH `ssh-add -l` and signs for
  OpenSSH `ssh`.

**LOC:** ~6,000 | **Duration:** 3-4 weeks

**Risks:**

| Risk | Severity | Mitigation |
|------|----------|-----------|
| PTY handling (termios, window size, signals) | High | Use `nix` crate for POSIX PTY; test with interactive programs (vim, top) |
| SFTP v3 vs v6 differences | Medium | Start with v3 (universally supported); add v6 extensions later |
| SOCKS5 proxy implementation | Medium | Small spec (RFC 1928); test with curl --socks5 |

---

### Phase 7: Server & Client

**Goal:** Build complete SSH server and client binaries.

**Deliverables:**

| Crate | Key Items |
|-------|-----------|
| `fsh-server` | TCP listener, per-connection session spawning, host key loading (Ed25519 + RSA), auth dispatch (pluggable authenticator chain), subsystem dispatch, privilege separation model, configuration file parsing, graceful shutdown |
| `fsh-client` | Connection establishment, `~/.ssh/config` parsing (subset), known_hosts management (TOFU + strict checking), agent forwarding, batch mode (`-n`, command arguments), interactive mode (terminal handling), multiplexed connections (future), connection reuse |

**Acceptance Criteria:**
- `fsh-server` accepts connections from OpenSSH `ssh` client; full session works.
- `fsh-client` connects to OpenSSH `sshd`; full session works.
- `fsh-client` connects to `fsh-server`; full session works (self-interop).
- Server handles 100 concurrent connections without resource leaks.
- Server handles connection storms (1000 rapid connects) gracefully.
- Known hosts: first connection adds host key; second connection verifies;
  changed host key triggers warning.
- Config: `Host`, `HostName`, `Port`, `User`, `IdentityFile`, `ServerAliveInterval`
  from `~/.ssh/config`.

**LOC:** ~5,000 | **Duration:** 2-3 weeks

**Risks:**

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Privilege separation complexity | High | Start with simple model (drop privileges after bind); enhance later |
| Config file compatibility with OpenSSH | Medium | Support common subset; document unsupported directives |
| Resource exhaustion under DoS | High | Connection rate limiting; per-IP limits; auth timeout; max channels per connection |

---

### Phase 8: Harness & Public API

**Goal:** Build the conformance test harness and stabilize the public API.

**Deliverables:**

| Crate | Key Items |
|-------|-----------|
| `fsh-harness` | Automated conformance tests (see §31), RFC test vectors, fuzz targets, performance benchmarks (Criterion), interoperability matrix |
| `frankenssh` | Stable public API facade, re-exports, documentation, examples |

**Acceptance Criteria:**
- Conformance harness passes >= 95% of test vectors.
- Interoperability matrix covers OpenSSH 8.x, 9.x on Linux and macOS.
- Public API has doc comments on all public items.
- `cargo doc` generates complete documentation.
- `frankenssh` crate can be used as a library to build a custom SSH client in < 50
  lines.

**LOC:** ~4,000 | **Duration:** 2-3 weeks

---

## 19. Phase Dependencies

```
Phase 1: Bootstrap
    |
    v
Phase 2: Types & Wire Format
    |
    +--------------------+
    |                    |
    v                    v
Phase 3: Crypto        (provides algorithms to all downstream)
    |
    v
Phase 4: Transport
    |
    +------------------+
    |                  |
    v                  v
Phase 5a: Auth     Phase 5b: Channels
    |                  |
    +--------+---------+
             |
             v
Phase 6: Session & Subsystems (sftp, forward, agent)
             |
             v
Phase 7: Server & Client
             |
             v
Phase 8: Harness & Public API
```

**Critical Path:** 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8

**Parallel Opportunities:**
- Phase 5a (Auth) and Phase 5b (Channels) can proceed in parallel.
- Phase 6 subsystems (sftp, forward, agent) can be developed in parallel
  once `fsh-channel` is ready.
- Phase 8 harness scaffolding can begin as soon as Phase 4 is functional.

---

## 20. LOC Estimates

| Phase | Crates | LOC | Cumulative |
|-------|--------|-----|-----------|
| 1 — Bootstrap | (all stubs) | 300 | 300 |
| 2 — Types & Wire | fsh-types, fsh-error, fsh-wire | 4,000 | 4,300 |
| 3 — Crypto | fsh-crypto | 3,000 | 7,300 |
| 4 — Transport | fsh-transport | 5,000 | 12,300 |
| 5 — Auth & Channels | fsh-auth, fsh-channel | 5,000 | 17,300 |
| 6 — Subsystems | fsh-session, fsh-sftp, fsh-forward, fsh-agent | 6,000 | 23,300 |
| 7 — Server & Client | fsh-server, fsh-client | 5,000 | 28,300 |
| 8 — Harness & API | fsh-harness, frankenssh | 4,000 | 32,300 |
| **Tests (all phases)** | | **~4,000** | **36,300** |

**Comparison with Legacy Source:**

| Metric | Legacy (C) | FrankenSSH (Rust) | Ratio |
|--------|-----------|------------------|-------|
| OpenSSH | ~110,000 LOC | ~36,300 LOC | 33% |
| OpenSSH + Dropbear + libssh2 | ~165,000 LOC | ~36,300 LOC | 22% |
| Unsafe code | 100% (C) | 0% (`#![forbid(unsafe_code)]`) | 0% |
| Test code (integrated) | ~0 (separate test suite) | ~4,000 LOC | N/A |

Reduction drivers:
- **Exclusions:** ~25% of OpenSSH code covers excluded features (X11, GSSAPI,
  compression, legacy ciphers, SSH-1, toolkit utilities).
- **No platform ifdefs:** OpenSSH supports ~15 platforms with extensive `#ifdef`
  chains. FrankenSSH targets Linux + macOS.
- **Library reuse:** `ring`, `tokio`, `clap`, `serde` replace hand-rolled
  equivalents.
- **Rust expressiveness:** Sum types, `Result<T, E>`, `?` operator, iterators,
  trait dispatch replace C error-handling boilerplate.
- **Type-state machine:** Eliminates thousands of lines of runtime state
  checking assertions.

---

# Part VI: Behavioral Extraction

This section is the seed for `EXISTING_SSH_STRUCTURE.md` — the first of the
four documents. It extracts the observable behavior of SSH-2 from the RFC corpus
and OpenSSH source.

## 21. OpenSSH Module Map

| Module | Source Files | LOC (est.) | Domain |
|--------|-------------|-----------|--------|
| Transport | `packet.c`, `kex.c`, `kexgen.c`, `kexdh.c`, `kexecdh.c`, `kexsntrup761x25519.c`, `cipher.c`, `cipher-chachapoly.c`, `cipher-aesctr.c`, `mac.c`, `umac.c`, `hmac.c` | ~18,000 | Binary packet protocol, key exchange, encryption, MAC |
| Auth | `auth.c`, `auth2.c`, `auth2-pubkey.c`, `auth2-passwd.c`, `auth2-kbdint.c`, `sshkey.c`, `ssh-ed25519.c`, `ssh-rsa.c`, `ssh-ecdsa.c` | ~15,000 | Authentication methods, key types, signing |
| Channels | `channels.c` | ~8,000 | Channel multiplexing, flow control, forwarding dispatch |
| Session | `session.c`, `serverloop.c` | ~6,000 | PTY, exec, env, signals, subsystem |
| SFTP | `sftp-server.c`, `sftp-client.c`, `sftp-common.c` | ~5,000 | File transfer subsystem |
| Agent | `ssh-agent.c`, `authfd.c` | ~3,000 | Key agent protocol |
| Config | `readconf.c`, `servconf.c`, `misc.c` | ~8,000 | Configuration parsing |
| Crypto/Buffers | `sshbuf.c`, `sshbuf-getput-*.c`, `digest-openssl.c` | ~5,000 | Secure buffers, digest wrappers |
| Client main | `ssh.c`, `sshconnect.c`, `sshconnect2.c` | ~8,000 | Client connection logic |
| Server main | `sshd.c`, `monitor.c`, `monitor_wrap.c` | ~10,000 | Server main loop, privilege separation |
| Utilities | `ssh-keygen.c`, `ssh-add.c`, `ssh-keyscan.c`, `scp.c` | ~12,000 | Excluded tooling |
| Platform | `openbsd-compat/*`, `entropy.c`, `audit-*.c` | ~12,000 | Platform compatibility shims |
| **Total** | | **~110,000** | |

---

## 22. Binary Packet Format

**Source:** RFC 4253 §6, OpenSSH `packet.c`

### 22.1 Unencrypted Packet

```
Offset  Size     Field
------  ----     -----
0       4        packet_length    Total bytes after this field (uint32, big-endian)
4       1        padding_length   Bytes of random padding (uint8)
5       N        payload          SSH message (N = packet_length - padding_length - 1)
5+N     P        padding          Random bytes (P = padding_length)
5+N+P   M        mac              MAC over entire unencrypted packet (M = mac_length; 0 before KEX)
```

**Constraints:**
- `packet_length` MUST be >= 12 and <= 35000 (configurable max).
- `padding_length` MUST be >= 4 and make total (4 + packet_length) a multiple
  of max(8, cipher_block_size).
- Padding bytes MUST be random.
- Maximum payload size: 32768 bytes (RFC recommendation).

### 22.2 Encrypted Packet (non-AEAD)

```
Encrypted:   E(packet_length || padding_length || payload || padding)
MAC:         MAC(seq_number || unencrypted_packet)
```

- Sequence number (`seq_number`) is an implicit u32 counter per direction,
  starting at 0, wrapping at 2^32.
- MAC is computed over the **unencrypted** packet with the sequence number
  prepended.
- Encrypt-then-MAC (ETM) variants compute MAC over ciphertext instead.

### 22.3 AEAD Packet (chacha20-poly1305, aes256-gcm)

For `chacha20-poly1305@openssh.com`:
```
packet_length:  4 bytes encrypted with separate ChaCha20 instance (K_2)
encrypted_data: ChaCha20 encrypted (K_1) payload + padding
poly1305_tag:   16 bytes Poly1305 over encrypted packet_length + encrypted_data
```

For `aes256-gcm@openssh.com`:
```
packet_length:  4 bytes unencrypted (used as AAD)
encrypted_data: AES-256-GCM encrypted payload + padding
gcm_tag:        16 bytes GCM authentication tag
```

---

## 23. Key Exchange Behavior

**Source:** RFC 4253 §7, OpenSSH `kex.c`, `kexgen.c`

### 23.1 Algorithm Negotiation

Both sides send `SSH_MSG_KEXINIT` (type 20):

```
byte      SSH_MSG_KEXINIT (20)
byte[16]  cookie (random)
name-list kex_algorithms
name-list server_host_key_algorithms
name-list encryption_algorithms_client_to_server
name-list encryption_algorithms_server_to_client
name-list mac_algorithms_client_to_server
name-list mac_algorithms_server_to_client
name-list compression_algorithms_client_to_server
name-list compression_algorithms_server_to_client
name-list languages_client_to_server
name-list languages_server_to_client
boolean   first_kex_packet_follows
uint32    0 (reserved)
```

**Selection algorithm:** For each category, the first algorithm in the
client's list that also appears in the server's list is selected. The client's
preference order wins.

### 23.2 Key Exchange (Curve25519)

For `curve25519-sha256`:

1. Client generates ephemeral X25519 keypair (e_C, Q_C = e_C * G).
2. Client sends `SSH_MSG_KEX_ECDH_INIT` with Q_C (32 bytes).
3. Server generates ephemeral X25519 keypair (e_S, Q_S = e_S * G).
4. Server computes shared_secret = X25519(e_S, Q_C).
5. Server computes exchange hash H = SHA-256(V_C || V_S || I_C || I_S ||
   K_S || Q_C || Q_S || K) where K = shared_secret.
6. Server signs H with host key.
7. Server sends `SSH_MSG_KEX_ECDH_REPLY` with K_S (host pubkey), Q_S,
   signature.
8. Client verifies signature and host key.
9. Client computes shared_secret = X25519(e_C, Q_S).
10. Client computes H and verifies.
11. Both sides send `SSH_MSG_NEWKEYS`.
12. Both sides derive session keys from K and H (see §23.3).

### 23.3 Key Derivation

After KEX, six keys are derived (RFC 4253 §7.2):

```
Initial IV (C->S):    HASH(K || H || "A" || session_id)
Initial IV (S->C):    HASH(K || H || "B" || session_id)
Encryption key (C->S): HASH(K || H || "C" || session_id)
Encryption key (S->C): HASH(K || H || "D" || session_id)
Integrity key (C->S):  HASH(K || H || "E" || session_id)
Integrity key (S->C):  HASH(K || H || "F" || session_id)
```

Where:
- K = shared secret (mpint encoding)
- H = exchange hash
- session_id = H from the **first** key exchange (never changes)
- HASH = negotiated hash function (SHA-256 for curve25519-sha256)

If key material is longer than hash output, extend:
```
K1 = HASH(K || H || X || session_id)
K2 = HASH(K || H || K1)
K3 = HASH(K || H || K1 || K2)
key = K1 || K2 || K3 || ...
```

---

## 24. Authentication Behavior

**Source:** RFC 4252, OpenSSH `auth2.c`, `auth2-pubkey.c`

### 24.1 Protocol Flow

1. Client sends `SSH_MSG_SERVICE_REQUEST "ssh-userauth"`.
2. Server sends `SSH_MSG_SERVICE_ACCEPT "ssh-userauth"`.
3. Client sends `SSH_MSG_USERAUTH_REQUEST`:
   ```
   string    username
   string    service_name ("ssh-connection")
   string    method_name ("publickey" | "password" | "keyboard-interactive")
   ... method-specific fields ...
   ```
4. Server responds with:
   - `SSH_MSG_USERAUTH_SUCCESS` (type 52) — authentication complete.
   - `SSH_MSG_USERAUTH_FAILURE` (type 51) — `name-list` of remaining methods +
     `boolean` partial_success.
   - `SSH_MSG_USERAUTH_PK_OK` (type 60) — pubkey is acceptable, now sign.
   - `SSH_MSG_USERAUTH_INFO_REQUEST` (type 60) — keyboard-interactive prompt.

### 24.2 Public Key Authentication

Two-phase:

**Phase 1 (query):**
```
SSH_MSG_USERAUTH_REQUEST:
  string  username
  string  "ssh-connection"
  string  "publickey"
  boolean FALSE              <-- query only, no signature
  string  public_key_algorithm ("ssh-ed25519", "rsa-sha2-256", etc.)
  string  public_key_blob
```

Server responds with `SSH_MSG_USERAUTH_PK_OK` if the key is acceptable.

**Phase 2 (prove):**
```
SSH_MSG_USERAUTH_REQUEST:
  string  username
  string  "ssh-connection"
  string  "publickey"
  boolean TRUE               <-- signature included
  string  public_key_algorithm
  string  public_key_blob
  string  signature           <-- signs session_id + this packet (without signature field)
```

### 24.3 Authentication Limits

- Default max attempts: 6 (OpenSSH `MaxAuthTries`).
- After max attempts: `SSH_DISCONNECT_NO_MORE_AUTH_METHODS_AVAILABLE`.
- Authentication timeout: 120 seconds (OpenSSH `LoginGraceTime`).

---

## 25. Channel Multiplexing Behavior

**Source:** RFC 4254, OpenSSH `channels.c`

### 25.1 Channel Open

```
SSH_MSG_CHANNEL_OPEN (90):
  string    channel_type ("session", "direct-tcpip", "forwarded-tcpip")
  uint32    sender_channel (our local channel ID)
  uint32    initial_window_size
  uint32    maximum_packet_size
  ... channel-type-specific data ...
```

Response: `SSH_MSG_CHANNEL_OPEN_CONFIRMATION` or `SSH_MSG_CHANNEL_OPEN_FAILURE`.

### 25.2 Window Management

SSH uses a sliding window for flow control:

- Each side advertises `initial_window_size` at channel open.
- Data sent decreases the remote window.
- `SSH_MSG_CHANNEL_WINDOW_ADJUST` (type 93) adds to the window:
  ```
  uint32  recipient_channel
  uint32  bytes_to_add
  ```
- Sender MUST NOT send data exceeding the remote window.
- Window size is per-channel, per-direction.
- OpenSSH default initial window: 64 * 32768 = 2MB.
- OpenSSH window adjust threshold: when local window drops below half,
  send adjust to restore to initial.

### 25.3 Channel Close Sequence

1. When done sending: `SSH_MSG_CHANNEL_EOF` (type 96).
2. To close channel: `SSH_MSG_CHANNEL_CLOSE` (type 97).
3. Upon receiving close, the other side MUST send close back.
4. Channel resources freed after both sides have sent and received close.

---

## 26. SFTP Subsystem Behavior

**Source:** draft-ietf-secsh-filexfer-02 (SFTP v3), OpenSSH `sftp-server.c`

### 26.1 Initialization

1. Client sends `SSH_FXP_INIT` with version 3.
2. Server responds with `SSH_FXP_VERSION` with agreed version + extensions.

### 26.2 Request-Response Model

Every SFTP request carries a `uint32 request_id`. Server responses include the
matching request_id. Requests may be pipelined (multiple outstanding).

### 26.3 Core Operations

| Type | Name | Description |
|------|------|-------------|
| 3 | `SSH_FXP_OPEN` | Open file (flags: READ, WRITE, CREAT, TRUNC, EXCL, APPEND) |
| 4 | `SSH_FXP_CLOSE` | Close file/directory handle |
| 5 | `SSH_FXP_READ` | Read up to N bytes from offset |
| 6 | `SSH_FXP_WRITE` | Write bytes at offset |
| 7 | `SSH_FXP_LSTAT` | Stat by path (no symlink follow) |
| 8 | `SSH_FXP_FSTAT` | Stat by handle |
| 9 | `SSH_FXP_SETSTAT` | Set attributes by path |
| 11 | `SSH_FXP_OPENDIR` | Open directory for reading |
| 12 | `SSH_FXP_READDIR` | Read directory entries |
| 13 | `SSH_FXP_REMOVE` | Delete file |
| 14 | `SSH_FXP_MKDIR` | Create directory |
| 15 | `SSH_FXP_RMDIR` | Remove directory |
| 16 | `SSH_FXP_REALPATH` | Canonicalize path |
| 18 | `SSH_FXP_RENAME` | Rename file/directory |
| 19 | `SSH_FXP_READLINK` | Read symlink target |
| 20 | `SSH_FXP_SYMLINK` | Create symbolic link |

### 26.4 Status Codes

| Code | Name | Meaning |
|------|------|---------|
| 0 | `SSH_FX_OK` | Success |
| 1 | `SSH_FX_EOF` | End of file/directory |
| 2 | `SSH_FX_NO_SUCH_FILE` | File not found |
| 3 | `SSH_FX_PERMISSION_DENIED` | Insufficient permissions |
| 4 | `SSH_FX_FAILURE` | Generic failure |
| 5 | `SSH_FX_BAD_MESSAGE` | Malformed request |
| 6 | `SSH_FX_NO_CONNECTION` | No connection |
| 7 | `SSH_FX_CONNECTION_LOST` | Connection lost |
| 8 | `SSH_FX_OP_UNSUPPORTED` | Operation not supported |

---

## 27. Agent Protocol Behavior

**Source:** draft-miller-ssh-agent, OpenSSH `ssh-agent.c`, `authfd.c`

### 27.1 Communication

Agent communicates over a Unix domain socket (`SSH_AUTH_SOCK` environment
variable). Messages use the same framing as SSH packets: `uint32 length` +
`byte type` + payload.

### 27.2 Message Types

| Type | Name | Direction | Description |
|------|------|-----------|-------------|
| 11 | `SSH2_AGENTC_REQUEST_IDENTITIES` | Client -> Agent | List all keys |
| 12 | `SSH2_AGENT_IDENTITIES_ANSWER` | Agent -> Client | Key list response |
| 13 | `SSH2_AGENTC_SIGN_REQUEST` | Client -> Agent | Sign data with key |
| 14 | `SSH2_AGENT_SIGN_RESPONSE` | Agent -> Client | Signature response |
| 17 | `SSH2_AGENTC_ADD_IDENTITY` | Client -> Agent | Add key to agent |
| 18 | `SSH2_AGENTC_REMOVE_IDENTITY` | Client -> Agent | Remove specific key |
| 19 | `SSH2_AGENTC_REMOVE_ALL_IDENTITIES` | Client -> Agent | Remove all keys |
| 25 | `SSH_AGENTC_ADD_SMARTCARD_KEY` | Client -> Agent | Add PKCS#11 key |

---

# Part VII: Feature Parity

## 28. Capability Matrix

| Capability | OpenSSH Reference | Status | Notes |
|-----------|-------------------|--------|-------|
| **Wire Format** | | | |
| Binary packet parsing (unencrypted) | `packet.c` | Planned | Phase 2 |
| Binary packet parsing (encrypted, non-AEAD) | `packet.c` | Planned | Phase 4 |
| Binary packet parsing (AEAD: chacha20-poly1305) | `cipher-chachapoly.c` | Planned | Phase 3-4 |
| Binary packet parsing (AEAD: aes256-gcm) | `cipher-aesctr.c` | Planned | Phase 3-4 |
| Sequence number management | `packet.c` | Planned | Phase 4 |
| Strict KEX extension (Terrapin mitigation) | `kex.c` | Planned | Phase 4 |
| Version string exchange | `sshconnect.c` | Planned | Phase 4 |
| **Key Exchange** | | | |
| curve25519-sha256 | `kexecdh.c` | Planned | Phase 3 |
| ecdh-sha2-nistp256 | `kexecdh.c` | Planned | Phase 3 |
| mlkem768x25519-sha256 (hybrid PQ) | N/A (innovation) | Planned | Phase 3 |
| sntrup761x25519-sha512 | `kexsntrup761x25519.c` | Planned | Phase 3 |
| diffie-hellman-group16-sha512 | `kexdh.c` | Planned | Phase 3 |
| diffie-hellman-group18-sha512 | `kexdh.c` | Planned | Phase 3 |
| **Ciphers** | | | |
| chacha20-poly1305@openssh.com | `cipher-chachapoly.c` | Planned | Phase 3 |
| aes256-gcm@openssh.com | `cipher-aesctr.c` | Planned | Phase 3 |
| aes256-ctr + hmac-sha2-256 | `cipher.c`, `mac.c` | Planned | Phase 3 |
| **Host Key Types** | | | |
| ssh-ed25519 | `ssh-ed25519.c` | Planned | Phase 3 |
| rsa-sha2-256 / rsa-sha2-512 | `ssh-rsa.c` | Planned | Phase 3 |
| ecdsa-sha2-nistp256 | `ssh-ecdsa.c` | Planned | Phase 3 |
| ssh-ed25519-cert-v01@openssh.com | `sshkey.c` | Planned | Phase 5 |
| **Authentication** | | | |
| publickey | `auth2-pubkey.c` | Planned | Phase 5 |
| password | `auth2-passwd.c` | Planned | Phase 5 |
| keyboard-interactive | `auth2-kbdint.c` | Planned | Phase 5 |
| certificate | `sshkey.c` | Planned | Phase 5 |
| auth banner | `auth2.c` | Planned | Phase 5 |
| partial success | `auth2.c` | Planned | Phase 5 |
| **Channels** | | | |
| session channel | `channels.c` | Planned | Phase 5 |
| direct-tcpip (local forwarding) | `channels.c` | Planned | Phase 6 |
| forwarded-tcpip (remote forwarding) | `channels.c` | Planned | Phase 6 |
| auth-agent@openssh.com (agent forwarding) | `channels.c` | Planned | Phase 6 |
| Window management (flow control) | `channels.c` | Planned | Phase 5 |
| **Session** | | | |
| PTY allocation (pty-req) | `session.c` | Planned | Phase 6 |
| Command execution (exec) | `session.c` | Planned | Phase 6 |
| Shell (shell) | `session.c` | Planned | Phase 6 |
| Environment variables (env) | `session.c` | Planned | Phase 6 |
| Signal forwarding (signal) | `session.c` | Planned | Phase 6 |
| Exit status (exit-status) | `session.c` | Planned | Phase 6 |
| Subsystem dispatch (subsystem) | `session.c` | Planned | Phase 6 |
| **SFTP** | | | |
| SFTP v3 init/version | `sftp-server.c` | Planned | Phase 6 |
| open/close/read/write | `sftp-server.c` | Planned | Phase 6 |
| stat/lstat/fstat/setstat | `sftp-server.c` | Planned | Phase 6 |
| opendir/readdir | `sftp-server.c` | Planned | Phase 6 |
| mkdir/rmdir/remove | `sftp-server.c` | Planned | Phase 6 |
| rename/symlink/readlink | `sftp-server.c` | Planned | Phase 6 |
| realpath | `sftp-server.c` | Planned | Phase 6 |
| **Agent** | | | |
| Request identities | `ssh-agent.c` | Planned | Phase 6 |
| Sign request | `ssh-agent.c` | Planned | Phase 6 |
| Add/remove identity | `ssh-agent.c` | Planned | Phase 6 |
| Key constraints (lifetime, confirm) | `ssh-agent.c` | Planned | Phase 6 |
| **Server** | | | |
| TCP listener + connection management | `sshd.c` | Planned | Phase 7 |
| Host key loading | `sshd.c` | Planned | Phase 7 |
| Privilege separation | `monitor.c` | Planned | Phase 7 |
| Configuration parsing | `servconf.c` | Planned | Phase 7 |
| **Client** | | | |
| Connection establishment | `sshconnect.c` | Planned | Phase 7 |
| Known hosts management | `hostfile.c` | Planned | Phase 7 |
| Config file parsing (subset) | `readconf.c` | Planned | Phase 7 |
| Agent forwarding | `ssh.c` | Planned | Phase 7 |

**Summary:**

| Domain | Implemented | Total | Coverage |
|--------|-------------|-------|----------|
| Wire format | 0 | 7 | 0% |
| Key exchange | 0 | 6 | 0% |
| Ciphers | 0 | 3 | 0% |
| Host keys | 0 | 4 | 0% |
| Authentication | 0 | 6 | 0% |
| Channels | 0 | 5 | 0% |
| Session | 0 | 7 | 0% |
| SFTP | 0 | 8 | 0% |
| Agent | 0 | 4 | 0% |
| Server | 0 | 4 | 0% |
| Client | 0 | 4 | 0% |
| **Overall** | **0** | **58** | **0%** |

---

## 29. Blocking Gaps

1. All features are currently unimplemented (project proposal stage).
2. Critical path to first usable SSH connection: Phases 1-5 (wire + crypto +
   transport + auth + channels).
3. Critical path to first SFTP transfer: Phases 1-6.
4. Critical path to production deployment: Phases 1-8 + security audit.

---

# Part VIII: Conformance & Testing

## 30. Testing Strategy

| Level | Framework | Scope |
|-------|-----------|-------|
| Unit tests | `#[cfg(test)]` + `proptest` | Individual functions, parsing, crypto operations |
| Integration tests | `tests/` per crate | Cross-function workflows (e.g., full KEX sequence) |
| Conformance tests | `fsh-harness` | End-to-end against real OpenSSH |
| Deterministic concurrency | `asupersync` lab runtime | Channel multiplexing, rekey races, window management |
| Fuzz tests | `cargo-fuzz` / `libfuzzer` | Packet parsing, SFTP commands, auth messages |
| Timing tests | `dudect` | MAC comparison, key derivation, signature verification |
| Benchmark tests | `criterion` | Handshake latency, throughput, channel overhead |

---

## 31. Conformance Harness Design

### 31.1 Architecture

```
fsh-harness:
  +--------------+         +-----------------+
  | fsh-client   | ------> | OpenSSH sshd    |  (in Docker/namespace)
  +--------------+         +-----------------+

  +--------------+         +-----------------+
  | OpenSSH ssh  | ------> | fsh-server      |  (in Docker/namespace)
  +--------------+         +-----------------+

  +--------------+         +-----------------+
  | fsh-client   | ------> | fsh-server      |  (self-interop)
  +--------------+         +-----------------+
```

### 31.2 Test Categories

| Category | Tests (Est.) | Description |
|----------|-------------|-------------|
| Version exchange | 10 | Version string parsing, malformed strings, long strings |
| Algorithm negotiation | 20 | All cipher/KEX/MAC combinations; missing algorithms; strict KEX |
| Key exchange | 15 | Each KEX algorithm; verify shared secret derivation; rekey |
| Host key verification | 10 | Ed25519, RSA-SHA2, ECDSA; unknown key; changed key; certificate |
| Authentication (pubkey) | 15 | Ed25519, RSA, ECDSA keys; wrong key; correct key; agent forwarded |
| Authentication (password) | 10 | Correct password, wrong password, empty password, max attempts |
| Authentication (kbd-interactive) | 10 | Simple prompt, multi-prompt, challenge-response |
| Channel open/close | 15 | Session, direct-tcpip; concurrent channels; rapid open/close |
| Window management | 10 | Large transfers; small windows; window adjust timing |
| Session (PTY) | 15 | Terminal modes; window resize; interactive programs |
| Session (exec) | 10 | Simple command; exit status; stderr; environment variables |
| SFTP operations | 25 | All SFTP commands; large files; symlinks; permissions; pipelining |
| Port forwarding | 15 | Local, remote, dynamic (SOCKS5); concurrent forwards |
| Agent protocol | 10 | Key listing; signing; add/remove; constraints |
| Rekey | 10 | Rekey during transfer; rekey timing; algorithm change |
| Error handling | 15 | Malformed packets; unsupported messages; sequence number wrap |
| Post-quantum | 10 | Hybrid KEX handshake; fallback when PQ not supported |
| Stress / DoS | 10 | Connection storms; channel exhaustion; large payloads |
| **Total** | **~225** | **Target: 95%+ pass rate** |

### 31.3 RFC Test Vectors

Specific test vectors extracted from RFCs:

| RFC | Test Vectors | Description |
|-----|-------------|-------------|
| RFC 7748 | 2 | X25519 shared secret computation |
| RFC 8032 | 7 | Ed25519 sign/verify |
| NIST FIPS 203 | TBD | ML-KEM-768 encapsulate/decapsulate |
| RFC 4253 §7.2 | Custom | Key derivation (capture from OpenSSH debug mode) |
| RFC 4252 | Custom | Auth protocol sequences |

---

## 32. Performance Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| Handshake latency (localhost) | < 10 ms (curve25519) | Custom benchmark |
| Handshake latency (hybrid PQ) | < 20 ms | Custom benchmark |
| Bulk transfer throughput | >= 500 MB/s (localhost, AES-GCM) | `fsh-harness` bench |
| Bulk transfer throughput | >= 400 MB/s (localhost, ChaCha20-Poly1305) | `fsh-harness` bench |
| Channel overhead | < 5% vs raw TCP | Comparative benchmark |
| SFTP throughput | >= 300 MB/s (large file) | SFTP benchmark |
| Memory per connection | < 1 MB (idle) | Profiling |
| Concurrent connections | 10,000+ (server) | Stress test |

---

# Part IX: Risk Management

## 33. Risk Summary Table

| # | Risk | Phase | Severity | Likelihood | Impact | Mitigation |
|---|------|-------|----------|-----------|--------|-----------|
| R1 | Crypto side-channel leaks | 3 | Critical | Low | Key compromise | Audited libraries only (`ring`, `rustcrypto`); timing tests; no custom crypto |
| R2 | OpenSSH interop failures | 4-7 | Critical | Medium | Unusable product | Conformance harness from Phase 4; test against OpenSSH 8.x, 9.x |
| R3 | Post-quantum standard flux | 3 | High | Medium | Wasted implementation effort | Feature flag for PQ; hybrid ensures classical fallback; track IETF drafts |
| R4 | Type-state API ergonomics | 4 | Medium | Medium | Poor developer experience | User testing; escape hatches; compare API with `thrussh`/`russh` |
| R5 | Timing attacks on auth | 5 | High | Medium | Auth bypass | Constant-time comparison for all secret-dependent operations |
| R6 | Channel window deadlock | 5 | High | Low | Connection hang | Proactive window adjust; timeout detection; test with asymmetric windows |
| R7 | PTY handling portability | 6 | Medium | Medium | Interactive sessions broken | `nix` crate for POSIX PTY; test with terminal programs |
| R8 | Privilege separation complexity | 7 | High | Medium | Security downgrade | Simple initial model (drop privs after bind); enhance incrementally |
| R9 | DoS via connection exhaustion | 7 | High | Medium | Server unavailability | Connection rate limits; per-IP limits; auth timeout; max channels |
| R10 | SFTP v3/v6 behavioral differences | 6 | Medium | Low | File transfer failures | Start with v3 (universal); add v6 extensions behind feature flag |
| R11 | Rekey during data transfer | 4 | High | Medium | Data loss or corruption | Buffer data during rekey; extensive testing with continuous transfer |
| R12 | Agent protocol file descriptor leaks | 6 | Medium | Low | Resource exhaustion | RAII handle management; test with rapid connect/disconnect |
| R13 | Known_hosts format compatibility | 7 | Medium | Medium | Confusing UX | Support OpenSSH format (hashed and unhashed); test with real files |
| R14 | Config file compatibility | 7 | Medium | Medium | Confusing UX | Support common subset; document unsupported directives explicitly |
| R15 | Memory safety in parsing | 2 | High | Low | RCE vulnerability | `forbid(unsafe_code)`; fuzz all parsers; bounded buffer sizes |

---

## 34. Security Model

### 34.1 Trust Boundaries

```
+-------------------+     +-------------------+
| Untrusted Network |---->| Transport Layer   |  Trust boundary #1:
|  (TCP stream)     |     | (parse, decrypt,  |  All input is untrusted.
+-------------------+     | verify MAC)       |  Parse errors = disconnect.
                          +--------+----------+
                                   |
                          +--------v----------+
                          | Auth Layer        |  Trust boundary #2:
                          | (verify identity) |  User not trusted until
                          +--------+----------+  authentication completes.
                                   |
                          +--------v----------+
                          | Channel Layer     |  Trust boundary #3:
                          | (multiplexed ops) |  Authenticated user has
                          +--------+----------+  permissions per channel.
                                   |
                          +--------v----------+
                          | Session Layer     |  Trust boundary #4:
                          | (exec, PTY, SFTP) |  Commands run as
                          +-------------------+  authenticated user.
```

### 34.2 Threat Matrix

| Threat | Mitigation |
|--------|-----------|
| Passive eavesdropping | Encryption (ChaCha20-Poly1305 / AES-256-GCM) |
| Active MITM | Host key verification (TOFU or certificate) |
| Harvest now, decrypt later (quantum) | ML-KEM-768 hybrid KEX |
| Terrapin attack (prefix truncation) | Strict-KEX OpenSSH extension (`kex-strict-c-v00@openssh.com` / `kex-strict-s-v00@openssh.com`) |
| Brute force auth | Max auth attempts + exponential backoff |
| DoS (connection flood) | Rate limiting + connection limits |
| Timing side-channels | Constant-time operations for all secret-dependent code |
| Buffer overflow / RCE | `#![forbid(unsafe_code)]` + fuzz testing |
| Replay attacks | Sequence numbers + session binding |

### 34.3 Constant-Time Requirements

The following operations MUST be constant-time (independent of secret values):

1. MAC verification (`ring::constant_time::verify_slices_are_equal`)
2. Password comparison (server-side auth)
3. Host key signature verification (the comparison, not the math)
4. HMAC computation (via `ring` which uses constant-time primitives)
5. Key derivation from shared secret

---

# Part X: FrankenFS Parallel

## 35. Methodology Correspondence

| Aspect | FrankenFS | FrankenSSH |
|--------|-----------|-----------|
| **Project type** | Filesystem reimplementation | Network protocol reimplementation |
| **Legacy corpus** | ext4/btrfs kernel C (~205K LOC) | OpenSSH C (~110K LOC) |
| **Legacy corpus type** | Kernel code (single module) | Userspace daemon (multiple binaries) |
| **Target interface** | FUSE (filesystem in userspace) | TCP socket (SSH-2 protocol) |
| **Innovation #1** | Block-level MVCC (replaces JBD2 global lock) | Post-quantum hybrid KEX (ML-KEM + X25519) |
| **Innovation #2** | RaptorQ self-healing (fountain-coded repair) | Type-state protocol machine (compile-time safety) |
| **Pure parsing crate** | `ffs-ondisk` (no I/O) | `fsh-wire` (no I/O) |
| **Storage/transport crate** | `ffs-block` (block device I/O + ARC cache) | `fsh-transport` (encrypted packet I/O + type-state) |
| **High-risk subsystem** | MVCC + SSI conflict detection | Crypto + key exchange + auth |
| **Conformance reference** | `dumpe2fs`, `fsck.ext4`, kernel ext4 driver | OpenSSH `ssh`, `sshd` |
| **`#![forbid(unsafe_code)]`** | Yes | Yes |
| **Cx integration** | Target contract: `&asupersync::Cx` on all I/O | Target contract: `&asupersync::Cx` on all I/O |
| **Doc methodology** | 4-document spec-first | 4-document spec-first |
| **Feature parity tracking** | `FEATURE_PARITY.md` + CI gate | `FEATURE_PARITY.md` + CI gate |
| **Parity tracking** | Quantitative parity report discipline | `FEATURE_PARITY.md` (currently 0/58) |
| **Estimated Rust LOC** | ~45,500 | ~36,300 |
| **Reduction from C** | 22% of legacy LOC | 22% of legacy LOC |
| **Crate count** | 21 (19 core + 2 legacy wrappers) | 15 |
| **Phase count** | 9 phases | 8 phases |
| **Critical path** | Parse -> I/O -> Tree -> Inode -> FUSE -> Repair -> CLI | Wire -> Crypto -> Transport -> Auth -> Session -> Server -> Harness |
| **Alien-artifact quality bar** | MVCC, repair policy, corruption decisions | Key exchange, auth state machine, side-channel mitigations |
| **Deterministic testing** | asupersync lab runtime (MVCC interleavings) | asupersync lab runtime (channel multiplexing races) |
| **Byte order** | Little-endian (ext4 on disk) | Big-endian (SSH network byte order) |
| **Error → errno mapping** | `FfsError` → POSIX errno (FUSE) | `FshError` → SSH disconnect reason codes |

### 35.1 What Transfers Directly

These FrankenFS patterns apply to FrankenSSH without modification:

1. **Four-document methodology** — identical workflow.
2. **`FEATURE_PARITY.md` with CI gate** — identical enforcement.
3. **Conformance harness architecture** — replace filesystem fixtures with
   SSH traffic captures.
4. **Workspace lint configuration** — identical `Cargo.toml` lints.
5. **Release profile** — identical optimization settings.
6. **Agent guidelines (AGENTS.md)** — identical rules (no deletion, no
   mass transforms, spec-first).
7. **Benchmark loop** — identical (baseline -> profile -> one lever -> prove
   equivalence -> re-measure).

### 35.2 What Adapts

1. **I/O model:** FrankenFS uses synchronous `pread`/`pwrite` (block device).
   FrankenSSH uses async TCP I/O (tokio). Cx integration adapts accordingly.
2. **Pure parsing layer:** FrankenFS parses on-disk structs (little-endian,
   fixed offsets). FrankenSSH parses wire protocol (big-endian, length-prefixed
   strings, mpint). Same principle (pure, no I/O), different encoding.
3. **Innovation layer:** FrankenFS innovates on storage (MVCC, repair).
   FrankenSSH innovates on security (PQ KEX) and correctness (type-state).
4. **Conformance harness:** FrankenFS compares metadata fields against
   `dumpe2fs`. FrankenSSH runs live handshakes against real OpenSSH.
5. **Error model:** FrankenFS maps to POSIX errno. FrankenSSH maps to SSH
   disconnect reason codes.

### 35.3 Lessons Learned from FrankenFS

These insights from the FrankenFS project experience inform the
FrankenSSH approach:

1. **Spec documents drift.** The `COMPREHENSIVE_SPEC` must be the single source
   of truth, with an explicit errata section for known code-vs-spec drift.
2. **Conformance harness catches what unit tests miss.** The FrankenFS fixture
   harness caught behavioral differences that unit tests alone would not have
   detected. FrankenSSH must start the conformance harness early (Phase 4).
3. **Pure parsing crates are the best investment.** `ffs-ondisk` is the
   most stable and reusable crate in FrankenFS. `fsh-wire` should get the
   same treatment: exhaustive round-trip tests and fuzz targets.
4. **Phase dependencies matter.** FrankenFS's Phase 6 (MVCC) could proceed
   in parallel with Phases 4-5 because it only depended on Phase 3 (block I/O).
   FrankenSSH's Phase 5 (Auth + Channels) can similarly be parallelized.
5. **Feature parity CI gate prevents regression.** The
   `parity_report_matches_feature_parity_md` test ensures the parity document
   stays accurate. This is critical for trust.

---

# Appendices

## A. Glossary

| Term | Definition |
|------|-----------|
| **SSH-2** | Secure Shell protocol version 2 (RFC 4251-4254). The only version FrankenSSH implements. |
| **KEX** | Key Exchange. The process of securely establishing a shared secret between client and server. |
| **ML-KEM** | Module-Lattice Key Encapsulation Mechanism (NIST FIPS 203). Post-quantum KEM based on lattice problems. |
| **CRQC** | Cryptographically Relevant Quantum Computer. A quantum computer capable of breaking current public-key cryptography. |
| **AEAD** | Authenticated Encryption with Associated Data. Combines encryption and integrity in a single operation (ChaCha20-Poly1305, AES-GCM). |
| **Type-state** | A design pattern that encodes protocol states as types, making invalid state transitions compile-time errors. |
| **Cx** | Capability context from `asupersync`. Carries cancellation tokens, deadlines, and structured concurrency scope. |
| **TOFU** | Trust On First Use. The default SSH host key verification model: accept key on first connection, reject changes. |
| **Strict KEX** | OpenSSH extension (`kex-strict-c-v00@openssh.com` / `kex-strict-s-v00@openssh.com`) that hardens KEX message sequencing against Terrapin-style prefix truncation attacks. |
| **mpint** | Multi-precision integer. SSH wire format for arbitrarily large integers (big-endian, sign-extended). |
| **name-list** | Comma-separated list of algorithm names in SSH wire format. |
| **FCW** | First-Committer-Wins. MVCC conflict resolution strategy. (FrankenFS term; included for cross-reference.) |
| **Window** | SSH channel flow control mechanism. Each direction has a window size; sender must not exceed it. |
| **Subsystem** | An SSH extension mechanism for running named protocols (e.g., "sftp") over a channel. |
| **ETM** | Encrypt-Then-MAC. A MAC construction that computes the MAC over the ciphertext, not the plaintext. More secure than MAC-then-encrypt. |

## B. Reference Materials

| Resource | Relevance |
|----------|-----------|
| OpenSSH source: `https://github.com/openssh/openssh-portable` | Primary legacy source for behavioral extraction |
| RFC 4251-4254 | Core SSH-2 protocol specification |
| RFC 8709 | Ed25519/Ed448 public keys for SSH |
| RFC 8332 | RSA-SHA2 signatures for SSH |
| RFC 8731 | Curve25519/448 key exchange |
| RFC 9142 | Updated KEX algorithms |
| NIST FIPS 203 | ML-KEM specification |
| draft-ietf-sshm-pq-ssh | Post-quantum SSH key exchange |
| draft-ietf-secsh-filexfer-02 | SFTP v3 specification |
| Megiddo & Modha, "ARC" (2003) | Referenced for methodology parallel with FrankenFS |
| Cahill, Rohm & Fekete, "SSI" (2008) | Referenced for methodology parallel with FrankenFS |
| `thrussh` / `russh` Rust SSH libraries | Prior art in Rust SSH implementations |

## C. Companion Document Status

The four-document workflow is already active in this repository:

### C.1 `EXISTING_SSH_STRUCTURE.md`

Behavioral extraction from OpenSSH source. Should continue expanding to cover:
- Every message type with complete field layouts
- State machine transition tables
- Algorithm negotiation edge cases
- Error behavior (when exactly does OpenSSH disconnect vs. ignore?)
- Behavioral quirks (OpenSSH-specific extensions not in RFCs)

### C.2 `PROPOSED_ARCHITECTURE.md`

Current crate architecture document. Should continue expanding to cover:
- Complete trait signatures (not just illustrative)
- Data-flow diagrams (handshake, data transfer, rekey, SFTP)
- Module structure within each crate
- Internal vs. public API boundaries

### C.3 `PLAN_TO_PORT_SSH_TO_RUST.md`

Operational porting plan. Should continue expanding to cover:
- Granular TODO checklist (per-crate, per-function)
- Phase acceptance test scripts
- CI pipeline configuration
- Release milestones

### C.4 `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md`

Canonical normative specification. This file now exists and supersedes other
docs on conflicts.

---

*This document is the top-level proposal for FrankenSSH. It defines scope,
methodology, architecture, and delivery plan, and is intended to stay aligned
with the active companion documents in the repository.*
