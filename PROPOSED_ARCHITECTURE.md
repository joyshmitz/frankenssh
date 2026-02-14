# PROPOSED_ARCHITECTURE.md — FrankenSSH (fsh)

> 15-crate Cargo workspace architecture for a memory-safe, clean-room Rust
> reimplementation of SSH-2 with post-quantum hybrid KEX and type-state
> protocol enforcement.

---

## 1. Crate Map

| # | Crate | Role | Key Dependencies | Phase |
|---|-------|------|-----------------|-------|
| 1 | `fsh-types` | Newtypes, binary helpers, SSH constants | `serde`, `thiserror` | 2 |
| 2 | `fsh-error` | `FshError` enum, disconnect reason mapping, `ParseError` re-export surface | `fsh-types`, `thiserror` | 2 |
| 3 | `fsh-wire` | Pure packet parse/serialize (no I/O) | `fsh-types`, `fsh-error` | 2 |
| 4 | `fsh-crypto` | Cipher suites, KEX, host keys, PQ hybrid | `fsh-types`, `fsh-error`, `ring`, crypto crates | 3 |
| 5 | `fsh-transport` | Type-state machine, encrypted I/O, rekey | `fsh-wire`, `fsh-crypto`, `asupersync` (planned) | 4 |
| 6 | `fsh-auth` | Auth methods, certificate validation | `fsh-wire`, `fsh-crypto`, `fsh-transport` | 5 |
| 7 | `fsh-channel` | Channel multiplexing, flow control | `fsh-wire`, `fsh-transport`, `asupersync` (planned) | 5 |
| 8 | `fsh-session` | PTY, exec, env, signals, subsystem | `fsh-channel`, `asupersync` (planned) | 6 |
| 9 | `fsh-sftp` | SFTP v3/v6 protocol | `fsh-wire`, `fsh-channel`, `asupersync` (planned) | 6 |
| 10 | `fsh-forward` | Port forwarding (local/remote/dynamic) | `fsh-channel`, `asupersync` (planned) | 6 |
| 11 | `fsh-agent` | SSH agent protocol | `fsh-wire`, `fsh-crypto`, `asupersync` (planned) | 6 |
| 12 | `fsh-server` | sshd equivalent | `fsh-transport`, `fsh-auth`, `fsh-channel`, `fsh-session`, `tokio` | 7 |
| 13 | `fsh-client` | ssh equivalent | `fsh-transport`, `fsh-auth`, `fsh-channel`, `fsh-session`, `fsh-agent`, `tokio` | 7 |
| 14 | `fsh-harness` | Conformance tests vs OpenSSH | `frankenssh`, `criterion`, `proptest` | 8 |
| 15 | `frankenssh` | Public API facade | re-exports core crates | 8 |

`asupersync` references above are architectural targets; in the current
workspace snapshot these dependencies are intentionally commented/deferred in
`Cargo.toml` until build-host availability is guaranteed.

---

## 2. Dependency Graph

```
fsh-types ─── fsh-error
     │             │
     └──────┬──────┘
            │
     ┌──────┼──────┐
     │      │      │
  fsh-wire  │  fsh-crypto
  (pure)    │  (ring etc)
     │      │      │
     └──────┼──────┘
            │
     fsh-transport
     (type-state)
            │
     ┌──────┼──────┐
     │             │
  fsh-auth    fsh-channel
     │             │
     │    ┌────┬───┼───┬────┐
     │    │    │   │   │    │
     │  session sftp fwd agent
     │    │    │   │   │    │
     └────┼────┼───┼───┼────┘
          │    │
    ┌─────┴────┘
    │
 ┌──┴───┐  ┌──────┐
 │server│  │client│
 └──┬───┘  └──┬───┘
    └────┬─────┘
         │
   frankenssh ─── fsh-harness
```

## 3. Layering Rules

1. `fsh-wire` is pure — no I/O, no async, no network.
2. `fsh-crypto` does not know about SSH framing.
3. `fsh-transport` owns the protocol state machine.
4. `fsh-auth` and `fsh-channel` depend on `fsh-transport` but not on each other.
5. Domain crates (session, sftp, forward, agent) depend on `fsh-channel`, not on `fsh-transport`.
6. `fsh-server`/`fsh-client` are integration crates with minimal business logic.
7. `fsh-harness` tests the public facade, not internals.

## 4. Key Traits

See `FRANKENSSH_PROPOSAL.md` Part III Section 11 for full trait definitions:
- `WirePacket` — pure parse/serialize
- `CipherSuite` — encrypt/decrypt/MAC
- `KexAlgorithm` — key exchange
- `Authenticator` — server-side auth
- `ChannelHandler` — channel event dispatch
