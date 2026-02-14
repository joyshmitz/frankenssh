# EXISTING_SSH_STRUCTURE

## 1. Legacy Oracle

- Root (workspace-relative): `legacy_openssh_code/openssh-portable`
- Upstream: `https://github.com/openssh/openssh-portable`
- Role: behavioral oracle for handshake sequences, auth flows, channel behavior, error responses, and wire format parity.

### 1.1 Local Checkout Policy

The OpenSSH oracle checkout is a **local, gitignored workspace dependency** and is
not required to be committed into this repository.

If the path is missing on a fresh clone, provision it locally:

```bash
mkdir -p legacy_openssh_code
git clone https://github.com/openssh/openssh-portable legacy_openssh_code/openssh-portable
```

Conformance preflight MUST assert this path exists locally before harness runs.

## 2. Subsystem Map

| Subsystem | Legacy Paths | Parity Critical Notes |
|---|---|---|
| Transport / packets | `packet.c`, `dispatch.c` | Binary packet framing, sequence numbers, padding, encryption/MAC application order |
| Key exchange | `kex.c`, `kexgen.c`, `kexdh.c`, `kexecdh.c`, `kexsntrup761x25519.c` | Algorithm negotiation order, strict KEX mode, exchange hash computation |
| Ciphers / MAC | `cipher.c`, `cipher-chachapoly.c`, `cipher-aesctr.c`, `mac.c`, `umac.c` | AEAD vs encrypt-then-MAC, key derivation from shared secret |
| Authentication | `auth.c`, `auth2.c`, `auth2-pubkey.c`, `auth2-passwd.c`, `auth2-kbdint.c` | Method ordering, partial success, max attempts, banner, timeout |
| Key types | `sshkey.c`, `ssh-ed25519.c`, `ssh-rsa.c`, `ssh-ecdsa.c` | Key parsing, signing, verification, certificate extensions |
| Channels | `channels.c` | Multiplexing, window management, flow control, channel types |
| Session | `session.c`, `serverloop.c` | PTY allocation, exec, env, signals, exit status, subsystem dispatch |
| SFTP | `sftp-server.c`, `sftp-client.c`, `sftp-common.c` | Request-response correlation, file handle lifecycle, v3 semantics |
| Agent | `ssh-agent.c`, `authfd.c` | Key listing, signing, add/remove, constraints |
| Config | `readconf.c`, `servconf.c` | Client/server configuration directives |
| Buffers | `sshbuf.c`, `sshbuf-getput-basic.c`, `sshbuf-getput-crypto.c` | Secure buffer read/write helpers, mpint encoding |

## 3. Semantics To Preserve Exactly (V1)

1. SSH-2 binary packet format (RFC 4253 §6) — framing, padding, sequence numbers.
2. Algorithm negotiation order (first algorithm in the client's preference list
   that is also supported by the server; RFC 4253 §7.1).
3. Key exchange: exchange hash computation, key derivation (RFC 4253 §7.2).
4. Authentication: method ordering, partial success, pubkey two-phase flow.
5. Channel: window management, close sequencing (EOF and CLOSE are distinct;
   CLOSE MAY be sent without prior EOF per RFC 4254 §5.3).
6. SFTP: request-ID correlation, status codes, v3 operation semantics.
7. Error responses: disconnect reason codes, error message strings.

## 4. Full Behavioral Extraction

### 4.1 Canonical Connection Phases

| Phase | Trigger In | Trigger Out | OpenSSH-observable contract |
|---|---|---|---|
| `Connected` | TCP accept/connect | version string received from peer | banner line protocol, line ending behavior |
| `VersionExchanged` | local+peer banners parsed | `SSH_MSG_KEXINIT` exchanged | strict parse of protocol version and comments |
| `KexInitExchanged` | both KEXINIT packets available | negotiated algorithms chosen | client-preference intersection (RFC 4253 §7.1), policy filtering |
| `KexRunning` | negotiated KEX handler entered | `SSH_MSG_NEWKEYS` both directions | exchange hash derivation and key schedule correctness |
| `Encrypted` | keys installed | `SSH_MSG_SERVICE_REQUEST`/`SSH_MSG_SERVICE_ACCEPT` (`ssh-userauth`) | explicit service gate before auth (RFC 4253 §10) |
| `Authenticating` | service accept completed | `SSH_MSG_USERAUTH_SUCCESS` | auth method loop with partial/failure semantics |
| `Authenticated` | auth success | first channel open | userauth gate lifts, channel API enabled |
| `Ready` | channel open confirm | channel eof/close/disconnect path | flow-control windows, request semantics |
| `Closing` | disconnect or close sequence | socket close | disconnect code/reason ordering |
| `Disconnected` | socket closed | terminal | no further protocol messages |

### 4.2 Version Exchange and KEXINIT Behavior

1. Peer version lines are newline-terminated; pre-banner garbage handling MUST
   match OpenSSH acceptance/rejection boundaries.
2. `SSH_MSG_KEXINIT` lists are ordered preferences; selection follows SSH
   negotiation semantics with compatibility-mode filtering.
3. Unknown algorithm names are ignored unless policy requires fail-closed
   (hardened mode).
4. Strict-KEX behavior follows OpenSSH 9.6+ Terrapin mitigations
   (`kex-strict-c-v00@openssh.com`, `kex-strict-s-v00@openssh.com`) and is
   distinct from RFC 8308 ext-info negotiation.

### 4.3 KEX and Key Material Behavior

1. Exchange hash composition MUST match negotiated KEX method and packet order.
2. Key derivation labels and session-id rules MUST follow RFC 4253 §7.2.
3. Rekey may be byte- or time-triggered; rekey MUST preserve active channels
   and message ordering guarantees.
4. Failure during KEX MUST terminate with deterministic disconnect reason and
   no partial key activation.

### 4.4 Authentication Behavior Extraction

#### 4.4.1 Method loop

1. Server returns allowed methods reactively in `SSH_MSG_USERAUTH_FAILURE`
   responses (RFC 4252 §5.1).
2. Client may retry methods until success or attempt limit.
3. Partial-success state is observable and MUST be preserved.

#### 4.4.2 Public key two-step flow

1. Probe request uses `boolean FALSE` in `SSH_MSG_USERAUTH_REQUEST` to check key
   acceptability.
2. Signed request uses `boolean TRUE` plus signature payload to finalize
   verification.
3. OpenSSH-specific ordering and failure codes around malformed signatures MUST
   be mirrored in strict mode.

#### 4.4.3 Password and keyboard-interactive

1. Prompt/response sequencing MUST maintain request-id and language-tag
   compatibility expectations.
2. Timeout and max-attempt policy are externally visible and MUST be
   deterministic.

### 4.5 Channel and Flow-Control Behavior

1. Channel IDs are per-direction namespaces; collisions are protocol errors.
2. Open -> confirm/failure ordering is strict.
3. Data/extended-data consume window credit; window adjust replenishes credit.
4. EOF and CLOSE are distinct signals. A common OpenSSH choreography is
   EOF -> CLOSE -> peer CLOSE acknowledgement path, but RFC 4254 §5.3 permits
   CLOSE without prior EOF.
5. Channel requests (`pty-req`, `exec`, `shell`, `env`, `signal`,
   `subsystem`) have request-success/failure semantics that MUST align with
   OpenSSH visible responses.

### 4.6 SFTP v3 Behavioral Baseline

1. `SSH_FXP_INIT`/`SSH_FXP_VERSION` negotiation is required entry gate.
2. Every request carries an ID; responses MUST preserve exact correlation.
3. Core operations (`open`, `close`, `read`, `write`, `stat`, `lstat`, `fstat`,
   `setstat`, `fsetstat`, `opendir`, `readdir`, `mkdir`, `rmdir`, `remove`,
   `rename`, `readlink`, `symlink`, `realpath`) are in-scope.
4. Status-code mapping (`SSH_FX_*`) must match OpenSSH-observable behavior for
   scoped operations.

### 4.7 Error and Disconnect Behavior

1. Protocol violations map to SSH disconnect reason codes, not ad hoc local
   errors.
2. Disconnect packets MUST be emitted before socket teardown when protocol state
   still permits transmission.
3. Error strings are observable; they MUST NOT leak secret material.
4. Unknown critical features in hardened mode fail closed; strict mode preserves
   OpenSSH-compatible tolerance where defined.

### 4.8 Oracle Validation Procedure

1. Validate behavior with `fsh-harness` against local OpenSSH oracle checkout:
   `legacy_openssh_code/openssh-portable`.
2. Capture packet traces for ambiguous cases and store as conformance artifacts.
3. Any observed divergence MUST be logged in parity notes and either fixed or
   explicitly recorded as an approved compatibility exception.

### 4.9 Cross-Reference

`FRANKENSSH_PROPOSAL.md` Part VI (Sections 21-27) remains the extended
walkthrough for packet layouts, KEX/auth/channel details, and subsystem notes.
