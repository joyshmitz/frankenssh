# FrankenSSH

FrankenSSH is a clean-room Rust reimplementation of SSH-2 targeting grand-scope excellence: wire compatibility, cryptographic rigor, post-quantum readiness, and compile-time protocol safety.

## What Makes This Project Special

Two crown-jewel innovations:

1. **Post-Quantum Hybrid Key Exchange:** ML-KEM-768 + X25519 hybrid protects against "harvest now, decrypt later" quantum threats while maintaining backward compatibility with classical-only peers.
2. **Type-State Protocol Machine:** Rust's type system encodes the SSH protocol state machine so that invalid transitions (e.g., sending data before authentication) are compilation errors, not runtime bugs.

## Methodological DNA

This project uses four pervasive disciplines:

1. alien-artifact-coding for decision theory, confidence calibration, and explainability.
2. extreme-software-optimization for profile-first, proof-backed performance work.
3. RaptorQ-everywhere for self-healing durability of long-lived trust/evidence artifacts.
4. frankenlibc/frankenfs compatibility-security thinking: strict vs hardened mode separation, fail-closed compatibility gates, and explicit drift ledgers.

## Current State

- Project charter and porting docs established
- 15-crate workspace scaffolded
- Core porting specs written (`EXISTING_SSH_STRUCTURE.md`, `PROPOSED_ARCHITECTURE.md`, `PLAN_TO_PORT_SSH_TO_RUST.md`, `FEATURE_PARITY.md`)
- Canonical normative spec authored (`COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md`)
- CI workflows authored under `.github/workflows` (`core`, `scope-gates`, `advisory-security`)
- Implementation not yet started (Phase 1: Bootstrap)
- OpenSSH oracle checkout is local/gitignored and may need bootstrap on a fresh clone

## Beads Planning Workflow

This repo uses Beads (`br`, beads_rust) for plan-space task orchestration once
initialized.

- Use `br` as the only mutation interface for issues/dependencies (`br create`,
  `br update`, `br close`, `br dep add/remove`).
- Keep planning-first discipline: validate dependency graph and acceptance
  criteria before implementation.
- Every implementation bead must define unit tests, e2e script commands, and
  structured logging requirements with evidence artifact locations.
- `br sync --flush-only` is non-invasive; persist task-state changes by staging
  `.beads/` in git explicitly.

## V1 Scope

- SSH-2 wire compatibility with OpenSSH
- Modern ciphers only (ChaCha20-Poly1305, AES-256-GCM, AES-256-CTR)
- Ed25519, RSA-SHA2, ECDSA host keys
- Pubkey, password, keyboard-interactive, certificate auth
- Channel multiplexing with flow control
- SFTP v3 subsystem
- Local/remote/dynamic port forwarding
- SSH agent protocol
- Server and client binaries

## Architecture Direction

```
TCP -> Wire parser -> Crypto suite -> Transport (type-state)
  -> Auth -> Channel mux -> Session/SFTP/Forward/Agent
  -> Server/Client binaries
```

## Compatibility and Security Stance

Preserve OpenSSH-observable handshake sequences, auth flows, channel behavior, and error responses. Defend against malformed frames, MITM, timing side-channels, and key compromise. Zero unsafe code.

## Performance and Correctness Bar

Track handshake latency, transfer throughput, and channel overhead; gate crypto operation regressions. Maintain SSH-2 wire compatibility, cryptographic correctness, and protocol state machine invariants.

## Key Documents

- `AGENTS.md`
- `FRANKENSSH_PROPOSAL.md` (comprehensive top-level proposal)
- `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md` (canonical normative spec)
- `EXISTING_SSH_STRUCTURE.md`
- `PROPOSED_ARCHITECTURE.md`
- `PLAN_TO_PORT_SSH_TO_RUST.md`
- `FEATURE_PARITY.md`
- `COMPATIBILITY_EXCEPTIONS.md` (approved compatibility deviations ledger)

## Porting Artifact Set

These four docs are the canonical porting-to-Rust workflow for this repo:

- `PLAN_TO_PORT_SSH_TO_RUST.md`
- `EXISTING_SSH_STRUCTURE.md`
- `PROPOSED_ARCHITECTURE.md`
- `FEATURE_PARITY.md`

Normative authority for conflict resolution:

- `COMPREHENSIVE_SPEC_FOR_FRANKENSSH_V1.md`

## Legacy Oracle Bootstrap

OpenSSH is used as the behavioral oracle at:

- `legacy_openssh_code/openssh-portable`

This path is intentionally gitignored as a local workspace dependency. If it's
missing:

```bash
mkdir -p legacy_openssh_code
git clone https://github.com/openssh/openssh-portable legacy_openssh_code/openssh-portable
```

Preflight before running conformance harness:

```bash
test -d legacy_openssh_code/openssh-portable || { echo "missing OpenSSH oracle checkout"; exit 1; }
```

## Validation Commands

```bash
cargo fmt --check
cargo check --all-targets
cargo clippy --all-targets -- -D warnings
cargo test --workspace
cargo test -p fsh-harness -- --nocapture
cargo bench -p fsh-harness
```
