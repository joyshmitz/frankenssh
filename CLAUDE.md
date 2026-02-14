# CLAUDE.md — FrankenSSH Session Context

## Project Origin

FrankenSSH was created by studying the FrankenFS repo (`/data/projects/frankenfs`) methodology
and applying the same four-document, spec-first approach to SSH-2. The project follows
the Dicklesworthstone franken* repo conventions observed across 11 sibling projects
(frankenfs, frankensearch, frankenredis, franken_networkx, franken_numpy, frankenscipy,
frankenpandas, frankenlibc, frankenjax, frankentorch, frankenterm).

## What Was Done (Bootstrap Session)

### 1. Methodology Analysis
- Read and analyzed the FrankenFS four-document methodology in depth:
  - `EXISTING_EXT4_BTRFS_STRUCTURE.md` (behavioral extraction)
  - `PROPOSED_ARCHITECTURE.md` (crate DAG)
  - `PLAN_TO_PORT_FRANKENFS_TO_RUST.md` (phased delivery)
  - `COMPREHENSIVE_SPEC_FOR_FRANKENFS_V1.md` (normative spec)
  - `FEATURE_PARITY.md` (quantitative tracking)
  - `AGENTS.md` (agent guidelines)

### 2. Proposal Written
- `FRANKENSSH_PROPOSAL.md` (2020 lines) — comprehensive top-level proposal covering:
  - Part I: Methodology (four-document approach)
  - Part II: Project Identity (PQ hybrid KEX + type-state innovations)
  - Part III: Architecture (15-crate DAG, key traits, error model, type-state machine)
  - Part IV: Scope (deliverables, 11 exclusions, platform, deps)
  - Part V: Phased Delivery (8 phases, ~36K LOC estimate)
  - Part VI: Behavioral Extraction (OpenSSH module map, packet format, KEX, auth, channels, SFTP, agent)
  - Part VII: Feature Parity (58 capabilities tracked)
  - Part VIII: Conformance & Testing (225 test categories, performance targets)
  - Part IX: Risk Management (15 risks, security model, threat matrix)
  - Part X: FrankenFS Parallel (methodology correspondence table)

### 3. Repo Organized
- Surveyed 11 franken* repos for common patterns
- Created repo matching conventions:
  - `git init` on `main` branch
  - Standard files: `.gitignore`, `rust-toolchain.toml`, `Cargo.toml` (workspace), `AGENTS.md`, `README.md`
  - Four porting docs: `EXISTING_SSH_STRUCTURE.md`, `PROPOSED_ARCHITECTURE.md`, `PLAN_TO_PORT_SSH_TO_RUST.md`, `FEATURE_PARITY.md`
  - 15 crate stubs in `crates/` + `frankenssh/` facade
  - `scripts/gates.sh` and `scripts/benchmark.sh`
  - All gates pass: fmt, check, clippy, test

### 4. Initial Commit
- `96c2ced` — 43 files, 5068 insertions, clean working tree

## Current State

- **Phase:** 1 (Bootstrap) — COMPLETE
- **Feature Parity:** 0/58 (0%)
- **Next Phase:** Phase 2 (Types & Wire Format) — `fsh-types`, `fsh-error`, `fsh-wire`
- **asupersync:** commented out in Cargo.toml deps (not available at `/dp/asupersync`); uncomment when available

## Key Architecture Decisions

- **Crate prefix:** `fsh-*` (like frankenfs uses `ffs-*`, frankenredis uses `fr-*`)
- **Innovation #1:** Post-quantum hybrid KEX (ML-KEM-768 + X25519)
- **Innovation #2:** Type-state protocol machine (compile-time state enforcement)
- **Pure parsing crate:** `fsh-wire` (no I/O, like `ffs-ondisk`)
- **Byte order:** Big-endian (SSH network byte order), opposite of ext4's little-endian
- **Async:** tokio for production, asupersync lab runtime for deterministic testing
- **Crypto:** audited libraries only (ring, rustcrypto crates), never custom crypto
- **Error mapping:** `FshError` → SSH disconnect reason codes (not POSIX errno like FrankenFS)

## Important Files

| File | Role |
|------|------|
| `FRANKENSSH_PROPOSAL.md` | Comprehensive proposal (start here for full context) |
| `AGENTS.md` | Agent rules, method stack, security doctrine |
| `FEATURE_PARITY.md` | Track implementation progress here |
| `PLAN_TO_PORT_SSH_TO_RUST.md` | Execution TODO checklist |
| `Cargo.toml` | Workspace manifest with all 15 crates |

## Sibling Projects for Reference

| Project | Path | Relevance |
|---------|------|-----------|
| FrankenFS | `/data/projects/frankenfs` | Primary methodology template (46.7% parity) |
| FrankenSQLite | `/data/projects/frankensqlite` | Oldest franken* project, strategy exemplar |
| FrankenRedis | `/data/projects/frankenredis` | Good example of conformance harness + strict/hardened mode |
| FrankenSearch | `/data/projects/frankensearch` | Good example of workspace deps + asupersync integration |
