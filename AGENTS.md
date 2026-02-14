# AGENTS.md — FrankenSSH (fsh)

> Guidelines for AI coding agents working in this Rust codebase.

---

## RULE 0 - THE FUNDAMENTAL OVERRIDE PREROGATIVE

If I tell you to do something, even if it goes against what follows below, YOU MUST LISTEN TO ME. I AM IN CHARGE, NOT YOU.

---

## RULE NUMBER 1: NO FILE DELETION

**YOU ARE NEVER ALLOWED TO DELETE A FILE WITHOUT EXPRESS PERMISSION.** Even a new file that you yourself created, such as a test code file. You have a horrible track record of deleting critically important files or otherwise throwing away tons of expensive work. As a result, you have permanently lost any and all rights to determine that a file or folder should be deleted.

**YOU MUST ALWAYS ASK AND RECEIVE CLEAR, WRITTEN PERMISSION BEFORE EVER DELETING A FILE OR FOLDER OF ANY KIND.**

---

## Irreversible Git & Filesystem Actions — DO NOT EVER BREAK GLASS

1. **Absolutely forbidden commands:** `git reset --hard`, `git clean -fd`, `rm -rf`, or any command that can delete or overwrite code/data must never be run unless the user explicitly provides the exact command and states, in the same message, that they understand and want the irreversible consequences.
2. **No guessing:** If there is any uncertainty about what a command might delete or overwrite, stop immediately and ask the user for specific approval. "I think it's safe" is never acceptable.
3. **Safer alternatives first:** When cleanup or rollbacks are needed, request permission to use non-destructive options (`git status`, `git diff`, `git stash`, copying to backups) before ever considering a destructive command.
4. **Mandatory explicit plan:** Even after explicit user authorization, restate the command verbatim, list exactly what will be affected, and wait for a confirmation that your understanding is correct. Only then may you execute it—if anything remains ambiguous, refuse and escalate.
5. **Document the confirmation:** When running any approved destructive command, record (in the session notes / final response) the exact user text that authorized it, the command actually run, and the execution time. If that record is absent, the operation did not happen.

---

## Git Branch: ONLY Use `main`, NEVER `master`

**The default branch is `main`. The `master` branch exists only for legacy URL compatibility.**

- **All work happens on `main`** — commits, PRs, feature branches all merge to `main`
- **Never reference `master` in code or docs** — if you see `master` anywhere, it's a bug that needs fixing
- **The `master` branch must stay synchronized with `main`** — after pushing to `main`, also push to `master`:
  ```bash
  git push origin main:master
  ```

---

## Toolchain: Rust & Cargo

We only use **Cargo** in this project, NEVER any other package manager.

- **Edition:** Rust 2024 (nightly required — see `rust-toolchain.toml`)
- **Unsafe code:** Forbidden (`#![forbid(unsafe_code)]` at crate roots + workspace lint)
- **Dependency versions:** Explicit versions for stability and reproducibility
- **Configuration:** `Cargo.toml` only

### Required Dependency Families

| Dependency | Purpose |
|------------|---------|
| `asupersync` | Async runtime, capability context (`Cx`), deterministic lab runtime |
| `tokio` | Production TCP I/O |
| `ring`, `chacha20poly1305`, `aes-gcm`, `x25519-dalek`, `ed25519-dalek` | Crypto primitives (audited libraries only) |
| `serde` + `serde_json` | Fixtures, conformance vectors, configuration |
| `thiserror` | Error modeling |
| `criterion`, `proptest`, `tempfile` | Bench + property/conformance testing |

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

1. alien-artifact-coding:
   - decision-theoretic runtime contracts
   - evidence ledgers
   - formal safety/calibration claims
2. extreme-software-optimization:
   - profile-first optimization
   - one optimization lever per change
   - behavior-isomorphism proof artifacts
3. RaptorQ-everywhere durability:
   - durable artifacts have repair-symbol sidecars
   - decode proofs for any recovery path
   - background integrity scrub requirements
4. frankenlibc/frankenfs security-compatibility doctrine:
   - strict compatibility mode + hardened mode separation
   - fail-closed on unknown incompatible features
   - explicit compatibility matrix and drift gates

---

## FrankenSSH — Project Identity

Crown-jewel innovations:

1. **Post-Quantum Hybrid Key Exchange:** ML-KEM-768 + X25519 hybrid protects against "harvest now, decrypt later" quantum threats.
2. **Type-State Protocol Machine:** Compile-time enforcement of SSH protocol ordering — invalid state transitions don't compile.

Legacy behavioral oracle:

- `/data/projects/frankenssh/legacy_openssh_code/openssh-portable`
- upstream: `https://github.com/openssh/openssh-portable`

CRITICAL NON-REGRESSION RULE:

SSH-2 wire compatibility with OpenSSH is a core contract for V1 scope. Every handshake, auth sequence, and channel operation must interoperate with real OpenSSH.

---

## Architecture (Target)

```
TCP stream -> Wire parser -> Crypto suite -> Transport (type-state)
  -> Auth -> Channel multiplexer -> Session/SFTP/Forward/Agent
  -> Server/Client binaries
```

Workspace crates (15):

| Crate | Role |
|-------|------|
| `fsh-types` | Newtypes, binary read/write helpers, SSH constants |
| `fsh-error` | `FshError` enum, SSH disconnect reason mapping |
| `fsh-wire` | Pure packet parse/serialize (no I/O) |
| `fsh-crypto` | Cipher suites, KEX algorithms, host key types, PQ hybrid |
| `fsh-transport` | Type-state protocol machine, encrypted I/O, rekey |
| `fsh-auth` | Authentication methods (pubkey, password, kbd-interactive, cert) |
| `fsh-channel` | Channel multiplexing, flow control, window management |
| `fsh-session` | PTY, exec, env, signals, subsystem dispatch |
| `fsh-sftp` | SFTP v3/v6 protocol |
| `fsh-forward` | Local/remote/dynamic port forwarding |
| `fsh-agent` | SSH agent protocol |
| `fsh-server` | sshd equivalent |
| `fsh-client` | ssh equivalent |
| `fsh-harness` | Conformance tests vs OpenSSH |
| `frankenssh` | Public API facade |

---

## Compatibility Doctrine (Mode-Split)

- strict mode:
  - maximize observable compatibility with OpenSSH
  - no behavior-altering innovations
- hardened mode:
  - preserve SSH-2 wire contract while adding PQ KEX, type-state safety
  - bounded defensive recovery for malformed packets and hostile edge cases

Compatibility focus for this project:

Preserve OpenSSH-observable handshake sequences, auth flows, channel behavior, and error responses for scoped algorithm/feature sets.

---

## Security Doctrine

Security focus for this project:

Defend against malformed protocol frames, MITM attacks, timing side-channels, and key compromise.

Minimum security bar:

1. Threat model notes for each major subsystem.
2. Fail-closed behavior for unknown/unsupported algorithms.
3. Adversarial fixture coverage and fuzz/property tests for parsers and crypto.
4. Constant-time operations for all secret-dependent code paths.
5. Deterministic audit logs for key exchange and authentication decisions.

---

## Required Spec Documents

These files are mandatory and must stay current:

1. `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md` (canonical source of truth)
2. `PLAN_TO_PORT_SSH_TO_RUST.md` (scope, exclusions, sequencing)
3. `EXISTING_SSH_STRUCTURE.md` (behavior extraction from OpenSSH)
4. `PROPOSED_ARCHITECTURE.md` (Rust crate/module architecture)
5. `FEATURE_PARITY.md` (measured parity status and gaps)

Reference exemplar:
- `COMPREHENSIVE_SPEC_FOR_FRANKENSQLITE_V1_REFERENCE.md` (strategy template from FrankenSQLite)

---

## Porting Doctrine (Spec-First, Conformance-First)

Follow this sequence:

1. **Extract behavior from OpenSSH code** into `EXISTING_SSH_STRUCTURE.md`
2. **Design Rust architecture** in `PROPOSED_ARCHITECTURE.md`
3. **Implement from spec** (not by copying C flow)
4. **Validate via conformance harness** (against real OpenSSH)
5. **Track parity numerically** in `FEATURE_PARITY.md`

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

### Benchmark Loop (mandatory)

- Baseline first (`hyperfine` / `criterion`)
- Profile hotspots
- Apply one optimization lever at a time
- Prove behavioral equivalence after each change
- Re-measure and record deltas

---

## Alien-Artifact Quality Bar

For high-risk subsystems (key exchange, authentication, crypto selection, timing-sensitive operations), prefer principled models over ad-hoc thresholds:

- Formal state machine diagrams for protocol transitions
- RFC test vectors for every cryptographic operation
- Timing analysis for side-channel resistance (`dudect`)
- Explicit threat models with trust boundary documentation

If a heuristic is used, document why formal alternatives were not viable.

---

## Required Check Commands (Post-Change)

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

## Performance Doctrine

Track handshake latency, transfer throughput, and channel overhead; gate crypto operation regressions.

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

- differential conformance report (vs OpenSSH)
- invariant checklist update
- benchmark delta report
- risk-note update if threat or compatibility surface changed

---

## Landing The Plane

Before ending a meaningful work session:

1. Confirm no destructive operations were run without explicit permission.
2. Summarize changes and rationale.
3. List residual risks and next highest-value steps.
4. Confirm method-stack artifacts were produced or explicitly deferred.
