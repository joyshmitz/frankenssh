# AGENTS.md — FrankenSSH (fsh)

> Guidelines for AI coding agents working in this Rust codebase.

---

## RULE 0 — HUMAN AUTHORITY

The human operator overrides everything below. Follow their instructions even when they contradict this document.

---

## RULE 1 — NO DELETIONS

No file or directory may be deleted without explicit written permission in the same message. This applies to files you created, test fixtures, generated artifacts — everything. Ask first, always.

---

## Irreversible Git & Filesystem Actions — DO NOT EVER BREAK GLASS

1. **Absolutely forbidden commands:** `git reset --hard`, `git clean -fd`, `rm -rf`, or any command that can delete or overwrite code/data must never be run unless the user explicitly provides the exact command and states, in the same message, that they understand and want the irreversible consequences.
2. **No guessing:** If there is any uncertainty about what a command might delete or overwrite, stop immediately and ask the user for specific approval. "I think it's safe" is never acceptable.
3. **Safer alternatives first:** When cleanup or rollbacks are needed, request permission to use non-destructive options (`git status`, `git diff`, `git stash`, copying to backups) before ever considering a destructive command.
4. **Mandatory explicit plan:** Even after explicit user authorization, restate the command verbatim, list exactly what will be affected, and wait for a confirmation that your understanding is correct. Only then may you execute it — if anything remains ambiguous, refuse and escalate.
5. **Document the confirmation:** When running any approved destructive command, record (in the session notes / final response) the exact user text that authorized it, the command actually run, and the execution time. If that record is absent, the operation did not happen.

---

## Git Branch: ONLY Use `main`, NEVER `master`

**The default branch is `main`. The `master` branch exists only for legacy URL compatibility.**

- **All work happens on `main`** — commits, PRs, feature branches all merge to `main`
- **Never reference `master` in code or docs** — if you see `master` anywhere, it's a bug
- **The `master` branch must stay synchronized with `main`** — after pushing to `main`, also push to `master`:
  ```bash
  git push origin main:master
  ```

---

## Toolchain: Rust & Cargo

We only use **Cargo** in this project, NEVER any other package manager.

- **Edition:** Rust 2024 (nightly required — see `rust-toolchain.toml`)
- **Unsafe code:** Forbidden (`#![forbid(unsafe_code)]` at crate roots + workspace lint). No exceptions without a signed-off security review.
- **Dependency versions:** Explicit versions for stability and reproducibility
- **Configuration:** `Cargo.toml` only

### Required Dependency Families

| Dependency | Purpose |
|------------|---------|
| `ring`, `chacha20poly1305`, `aes-gcm`, `x25519-dalek`, `ed25519-dalek`, `sha2` | Crypto primitives — audited, published crates only. Never hand-rolled crypto. |
| `tokio` | Production async TCP I/O, timers, signals |
| `asupersync` | Deterministic lab runtime for concurrency testing. Commented out until available at build host. |
| `serde` + `serde_json` | Configuration, conformance vectors, test fixtures |
| `thiserror` | Structured error types mapping to SSH disconnect reasons |
| `criterion`, `proptest`, `tempfile` | Benchmarks, property tests, ephemeral key material |

### Release Profile (size-optimized)

```toml
[profile.release]
opt-level = "z"
lto = true
codegen-units = 1
panic = "abort"
strip = true
```

---

## Mandatory Method Stack (Non-Negotiable)

Every meaningful implementation decision must apply all four methods:

1. **alien-artifact-coding:**
   - Protocol state diagrams with every transition explicitly labeled
   - RFC test vectors as evidence for every cryptographic operation
   - Formal threat models per subsystem with trust boundaries, attacker capabilities, mitigations
   - If a heuristic replaces a formal approach, document what was considered and why it was rejected
2. **extreme-software-optimization:**
   - Profile-first — measure before optimizing
   - One optimization lever per change
   - Behavior-isomorphism proof: conformance harness must pass identically before and after
3. **RaptorQ-everywhere durability:**
   - Durable trust artifacts (host key databases, known_hosts state, session resumption token stores, conformance/benchmark evidence bundles) carry repair-symbol sidecars
   - Decode proofs for any recovery or resumption path
   - Background integrity verification for persistent credential stores
4. **frankenlibc/frankenfs security-compatibility doctrine:**
   - Strict compatibility mode + hardened mode separation
   - Fail-closed on unknown or unsupported algorithms
   - Explicit compatibility matrix and drift gates against OpenSSH releases

---

## FrankenSSH — Project Identity

Crown-jewel innovations:

1. **Post-Quantum Hybrid Key Exchange:** ML-KEM-768 lattice encapsulation composed with X25519 ECDH. Classical security is never weaker than X25519 alone; post-quantum security is added, not substituted.
2. **Type-State Protocol Machine:** The SSH state machine (version exchange → KEX → authentication → channel operations) is encoded in Rust's type system. `Session<Unauthenticated>` cannot call channel methods. Transitions consume `self` and return the next state. Invalid sequences are compile errors.

### Legacy Behavioral Oracle

OpenSSH portable is the behavioral reference:
- Path: `legacy_openssh_code/openssh-portable`
- Upstream: `https://github.com/openssh/openssh-portable`

The oracle checkout is expected to be local and gitignored. If absent, provision:
```bash
mkdir -p legacy_openssh_code
git clone https://github.com/openssh/openssh-portable legacy_openssh_code/openssh-portable
```

OpenSSH defines "correct" for every ambiguous RFC passage. When RFCs conflict with OpenSSH behavior in practice, document the divergence and default to OpenSSH's interpretation for strict mode.

### CRITICAL NON-REGRESSION RULE

SSH-2 wire compatibility with OpenSSH is not a goal — it is a constraint. Every handshake, every auth exchange, every channel lifecycle must complete successfully against a stock OpenSSH peer. If it doesn't, the implementation is wrong regardless of what the code looks like internally.

---

## Architecture (Target)

```
TCP → fsh-wire (parse) → fsh-crypto (decrypt/verify)
    → fsh-transport (type-state machine, rekey)
    → fsh-auth (pubkey, password, kbd-interactive, cert)
    → fsh-channel (multiplex, flow control, windows)
    → fsh-session / fsh-sftp / fsh-forward / fsh-agent
    → fsh-server / fsh-client (binaries)
    → fsh-harness (conformance vs real OpenSSH)
    → frankenssh (public API facade)
```

Fifteen crates. Every dependency arrow points downward. No cycles.

| Layer | Crates | I/O allowed? |
|---|---|---|
| Primitives | `fsh-types`, `fsh-error` | No |
| Wire format | `fsh-wire` | No — pure parse/serialize, zero allocation in hot path |
| Crypto | `fsh-crypto` | No network I/O; entropy source is injected |
| Protocol engine | `fsh-transport`, `fsh-auth`, `fsh-channel` | Async I/O via trait abstraction |
| Subsystems | `fsh-session`, `fsh-sftp`, `fsh-forward`, `fsh-agent` | Through channel layer only |
| Binaries | `fsh-server`, `fsh-client` | Full I/O — tokio runtime |
| Testing | `fsh-harness` | Full I/O — spawns real OpenSSH |
| Facade | `frankenssh` | Re-exports, no logic |

### Design Constraints

1. **Spec-first, not translation.** Read OpenSSH to understand what happens. Read RFCs to understand why. Then write Rust that satisfies both without copying the C control flow.
2. **`fsh-wire` is the trust boundary.** All untrusted bytes from the network pass through `fsh-wire` before reaching any other crate. It must reject malformed input without panicking, leaking memory, or consuming unbounded resources.
3. **Crypto operations are opaque to protocol logic.** `fsh-transport` sees trait methods (`encrypt`, `decrypt`, `sign`, `verify`), never raw key material.
4. **Type-state transitions are the protocol spec.** If you can call a method, the protocol allows it. If you can't, it doesn't.
5. **Errors carry disconnect reasons.** `FshError` maps to SSH disconnect reason codes (RFC 4253 §11.1). Error handling is part of the wire contract, not an afterthought.

---

## Compatibility Doctrine (Mode-Split)

- **strict mode:**
  - Maximize observable compatibility with deployed OpenSSH
  - Accept and ignore unknown extensions (OpenSSH compat)
  - Follow OpenSSH rekey intervals and algorithm negotiation order
  - All supported host key algorithms available
- **hardened mode:**
  - Modern-only algorithms + PQ hybrid KEX
  - Reject and disconnect on unknown extensions
  - Aggressive rekey (1 GB / 1 hour)
  - Ed25519 + certificates only
  - Bounded defensive recovery for malformed packets

Both modes use the same type-state engine. The difference is policy, not plumbing.

Compatibility focus: preserve OpenSSH-observable handshake sequences, auth flows, channel behavior, and error responses for scoped algorithm/feature sets.

---

## Security Doctrine

SSH operates in an adversarial network. Every byte from the peer is potentially hostile.

### Threat Priorities

1. **Key compromise** — forward secrecy, PQ resistance, rekey intervals.
2. **MITM** — strict host key verification, no fallback to weaker algorithms.
3. **Timing side-channels** — constant-time comparison for MACs, signatures, password checks.
4. **Parser exploitation** — bounded reads, no panics on malformed input, allocation limits.
5. **State confusion** — type-state machine prevents acting on data from wrong protocol phase.

### Non-Negotiable Security Rules

- No plaintext secrets in logs, errors, or debug output.
- Key material is zeroized on drop (`zeroize` crate or equivalent).
- Random number generation uses OS entropy only (`ring::rand::SystemRandom` or equivalent).
- No algorithm downgrade without explicit user opt-in.
- Certificate validation failures are hard errors, never warnings.

### Minimum Security Bar

1. Threat model notes for each major subsystem.
2. Fail-closed behavior for unknown/unsupported algorithms.
3. Adversarial fixture coverage and fuzz/property tests for parsers and crypto.
4. Constant-time operations for all secret-dependent code paths.
5. Side-channel analysis (`dudect` or equivalent) for secret-dependent paths.

---

## RaptorQ-Everywhere Contract

For any durable artifact that FrankenSSH manages (host key databases, known_hosts state, persistent session resumption tokens, serialized configurations, conformance/benchmark evidence bundles):

1. **Repair-symbol sidecars** — fountain-coded redundancy alongside the primary artifact.
2. **Decode proofs** — verifiable recovery path for any restoration operation.
3. **Background integrity scrub** — periodic verification of persistent credential stores.

Required outputs:

1. Repair-symbol generation manifest.
2. Integrity scrub report.
3. Decode proof artifact for each recovery event.

For ephemeral session state (in-flight keys, channel buffers), RaptorQ does not apply — forward secrecy and zeroization govern those lifecycles instead.

---

## Required Spec Documents

These files are mandatory and must stay current:

1. `EXISTING_SSH_STRUCTURE.md` (behavior extraction from OpenSSH — what it does, observable contracts)
2. `PROPOSED_ARCHITECTURE.md` (Rust crate/module architecture, trait contracts, dependency DAG)
3. `PLAN_TO_PORT_SSH_TO_RUST.md` (scope, exclusions, phased delivery, acceptance criteria)
4. `FEATURE_PARITY.md` (measured parity status — 58 capabilities across 11 domains)
5. `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md` (canonical normative spec; supersedes other docs on conflicts)

---

## Porting Doctrine (Spec-First, Conformance-First)

Follow this sequence:

1. **Extract behavior from OpenSSH** into `EXISTING_SSH_STRUCTURE.md` — what packets does it send, in what order, what happens on error? Focus on the what, ignore the how.
2. **Design Rust architecture** in `PROPOSED_ARCHITECTURE.md` — crate boundaries, trait signatures, type-state transitions.
3. **Implement from spec** (not by copying C flow). If you find yourself reading `packet.c` line by line while coding, stop.
4. **Validate via conformance harness** against real OpenSSH. Unit tests for edge cases. Property tests for parsers.
5. **Track parity numerically** in `FEATURE_PARITY.md` in the same commit that implements the feature.

### Explicit Exclusions

Anything excluded must be listed explicitly in:
- `PLAN_TO_PORT_SSH_TO_RUST.md`
- `FEATURE_PARITY.md`

Hidden exclusions are not allowed.

---

## Code Editing Discipline

### No Script-Based Mass Code Transformations

**NEVER** run scripts that bulk rewrite code in this repo.

- Make code edits manually
- For repetitive edits, use subagents or careful targeted patches
- For subtle logic, read and reason before editing

### No File Proliferation

- Modify existing files when functionality belongs there
- Do not create `*_v2`, `*_new`, or similar variants
- New files are allowed only for genuinely new functionality

---

## Conformance and Benchmarking Requirements

FrankenSSH must include:

1. **Fixture-based conformance tests** (goldens for SSH handshake, auth, channel behavior)
2. **Legacy behavior mapping** (feature-to-source traceability)
3. **Benchmark suite** with baselines and regression detection
4. **Feature parity report** with explicit percentages and blocked items

### Conformance Targets

- **Handshake:** Complete KEX with OpenSSH sshd and ssh client for every supported algorithm combination.
- **Auth:** Every auth method tested against OpenSSH with valid and invalid credentials.
- **Channels:** Session, exec, subsystem, forwarding — tested end-to-end.
- **Errors:** Verify that error responses match OpenSSH disconnect codes and sequences.
- **Goldens:** Captured packet traces for regression detection.

---

## Performance Doctrine

Track handshake latency, transfer throughput, and channel overhead; gate crypto operation regressions.

| Metric | What it measures |
|---|---|
| Handshake latency | TCP connect to authenticated session (p50/p95/p99) |
| Transfer throughput | Sustained bulk data over established channel (MB/s) |
| Channel overhead | Per-packet processing for multiplexed channels (ns/packet) |

Mandatory optimization loop:

1. Baseline: record p50/p95/p99 and memory.
2. Profile: identify real hotspots.
3. Implement one optimization lever.
4. Prove behavior unchanged via conformance + invariant checks.
5. Re-baseline and emit delta artifact.

---

## Correctness Doctrine

Maintain SSH-2 wire compatibility, cryptographic correctness, and protocol state machine invariants.

Required evidence for substantive changes:

- Differential conformance report (vs OpenSSH)
- Invariant checklist update
- Benchmark delta report
- Risk-note update if threat or compatibility surface changed

---

## Compiler/Lint/Test Gates (CRITICAL)

After substantive changes, you MUST run:

```bash
cargo fmt --check
cargo check --all-targets
cargo clippy --all-targets -- -D warnings
cargo test --workspace
```

For conformance/bench work, also run:

```bash
cargo test -p fsh-harness -- --nocapture
cargo bench -p fsh-harness
```

If a gate fails, fix root causes instead of suppressing diagnostics.

---

## Landing The Plane

Before ending a meaningful work session:

1. Confirm no destructive operations were run without explicit permission.
2. Summarize changes and rationale.
3. List residual risks and next highest-value steps.
4. Confirm method-stack artifacts were produced or explicitly deferred.
