# FEATURE_PARITY

> Quantitative feature coverage tracking for FrankenSSH.

## Status Legend

- not_started
- in_progress
- parity_green
- parity_gap

Scope note:

- SFTP v3 is parity-gated for V1.
- SFTP v6 is optional extension scope and is not counted in the 58 tracked
  capabilities unless explicitly added to this matrix.
- Phase 2 readiness gates (below) track foundation completeness and evidence,
  but do not increase the 58-capability parity count until behavior-level
  feature rows turn green.

## 1. Coverage Summary (Current)

| Domain | Implemented | Total Tracked | Coverage |
|--------|-------------|---------------|----------|
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

## 1.1 Phase 2 Readiness Gates (Non-Parity-Gating)

| Phase 2 Gate | Status | Acceptance Evidence |
|---|---|---|
| `fsh-types` foundational newtypes | not_started | API/type inventory with invariants checklist |
| `fsh-types` binary helpers (`read_*`/`write_*`) | not_started | Unit tests for bounds/truncation/mpint/name-list cases |
| `fsh-error` + `ParseError` taxonomies | not_started | Variant inventory and review notes |
| `fsh-error` disconnect reason mapping | not_started | Mapping table with RFC 4253 §11.1 references |
| `fsh-wire` message baseline + `WirePacket` trait | not_started | Message coverage matrix vs Phase 2 baseline list |
| Message-level round-trip suite | not_started | Byte-for-byte round-trip test report |
| Property-based parser/serializer tests | not_started | `proptest` run summary + seed/repro notes |
| Parser fuzz target (panic-free) | not_started | Fuzz run summary with crash status and corpus notes |
| OpenSSH fixture parsing | not_started | Captured handshake parse transcript |

## 2. Parity Matrix

| Feature Family | Status | Notes |
|---|---|---|
| Binary packet parsing (unencrypted) | not_started | Phase 2 |
| Binary packet parsing (AEAD: chacha20-poly1305) | not_started | Phase 3-4 |
| Binary packet parsing (AEAD: aes256-gcm) | not_started | Phase 3-4 |
| Binary packet parsing (encrypted, non-AEAD) | not_started | Phase 4 |
| Sequence number management | not_started | Phase 4 |
| Strict KEX extension | not_started | Phase 4 |
| Version string exchange | not_started | Phase 4 |
| curve25519-sha256 KEX | not_started | Phase 3 |
| ecdh-sha2-nistp256 KEX | not_started | Phase 3 |
| mlkem768x25519-sha256 hybrid PQ KEX | not_started | Phase 3 |
| sntrup761x25519-sha512 KEX | not_started | Phase 3 |
| diffie-hellman-group16-sha512 KEX | not_started | Phase 3 |
| diffie-hellman-group18-sha512 KEX | not_started | Phase 3 |
| chacha20-poly1305@openssh.com cipher | not_started | Phase 3 |
| aes256-gcm@openssh.com cipher | not_started | Phase 3 |
| aes256-ctr + hmac-sha2-256 cipher | not_started | Phase 3 |
| ssh-ed25519 host key | not_started | Phase 3 |
| rsa-sha2-256/512 host key | not_started | Phase 3 |
| ecdsa-sha2-nistp256 host key | not_started | Phase 3 |
| ssh-ed25519-cert-v01 host key | not_started | Phase 5 |
| publickey auth | not_started | Phase 5 |
| password auth | not_started | Phase 5 |
| keyboard-interactive auth | not_started | Phase 5 |
| certificate auth | not_started | Phase 5 |
| auth banner | not_started | Phase 5 |
| auth partial success | not_started | Phase 5 |
| session channel | not_started | Phase 5 |
| direct-tcpip channel | not_started | Phase 6 |
| forwarded-tcpip channel | not_started | Phase 6 |
| auth-agent channel | not_started | Phase 6 |
| window management | not_started | Phase 5 |
| PTY allocation | not_started | Phase 6 |
| command execution | not_started | Phase 6 |
| shell | not_started | Phase 6 |
| environment variables | not_started | Phase 6 |
| signal forwarding | not_started | Phase 6 |
| exit status | not_started | Phase 6 |
| subsystem dispatch | not_started | Phase 6 |
| SFTP init/version | not_started | Phase 6 |
| SFTP open/close/read/write | not_started | Phase 6 |
| SFTP stat/lstat/fstat/setstat | not_started | Phase 6 |
| SFTP opendir/readdir | not_started | Phase 6 |
| SFTP mkdir/rmdir/remove | not_started | Phase 6 |
| SFTP rename/symlink/readlink | not_started | Phase 6 |
| SFTP realpath | not_started | Phase 6 |
| Agent: request identities | not_started | Phase 6 |
| Agent: sign request | not_started | Phase 6 |
| Agent: add/remove identity | not_started | Phase 6 |
| Agent: key constraints | not_started | Phase 6 |
| Server: TCP listener + connection mgmt | not_started | Phase 7 |
| Server: host key loading | not_started | Phase 7 |
| Server: privilege separation | not_started | Phase 7 |
| Server: configuration parsing | not_started | Phase 7 |
| Client: connection establishment | not_started | Phase 7 |
| Client: known_hosts management | not_started | Phase 7 |
| Client: config file parsing | not_started | Phase 7 |
| Client: agent forwarding | not_started | Phase 7 |
| Differential conformance harness | not_started | Phase 8 |
| Benchmark + optimization artifacts | not_started | Phase 8 |

## 3. Required Evidence Per Feature Family

1. Differential conformance report (vs real OpenSSH).
2. Edge-case/adversarial test results.
3. Benchmark delta (when performance-sensitive).
4. Documented compatibility exceptions (if any).

## 4. Blocking Gaps to 100%

1. All features currently unimplemented (project at bootstrap stage).
2. Critical path to first SSH connection: Phases 1-5.
3. Critical path to first SFTP transfer: Phases 1-6.
4. Critical path to production: Phases 1-8 + security audit.

## 5. Update Rule

Any change touching protocol behavior MUST update this file in the same patch.
